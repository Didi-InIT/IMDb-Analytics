DROP VIEW IF EXISTS us_display_title;
CREATE VIEW us_display_title AS
SELECT 
	DISTINCT ON (titleid) titleid, 
	ordering,
	title
FROM title_akas
WHERE region = 'US' 
ORDER BY 
	titleid,
	CASE WHEN types='imdbDisplay' THEN 0 ELSE 1 END,
    ordering;

/* 
View to select all the movies for the region US, with a distinct prioritizing imdbDisplay as display type and
a lower ordering value since the combination titleid/ordering is the Primary Key of title_akas table.
*/


-- ############################################################
-- QUERY 1: Top Movies — Bayesian Ranking
-- Objective: Rank movies using a Bayesian estimate to avoid instability from low-vote titles.
-- Logic: Combine each movie’s own rating (R) with the global mean (C), weighted by its votes (v)
--        against a prior weight (m), where m = p80(numvotes):
--            score = (v/(v+m)) * R  +  (m/(v+m)) * C
--        Thus, more votes → more influence of the movie’s rating; few votes → pull towards C.
-- ############################################################

WITH stats AS( 
SELECT 
	AVG(r.averagerating) AS global_mean,
	PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY r.numvotes) AS p80_nr_votes
FROM us_display_title us
JOIN title_ratings r ON r.tconst = us.titleid
)

SELECT us.titleid,
	us.title,
	r.numvotes,
	r.averagerating AS original_rating,
	round(((r.numvotes / (r.numvotes + s.p80_nr_votes)) * r.averagerating + (s.p80_nr_votes / (r.numvotes + s.p80_nr_votes)) * s.global_mean)::numeric, 2) as bayesian_ranking
FROM us_display_title us
JOIN title_ratings r ON r.tconst = us.titleid
CROSS JOIN stats s
ORDER BY 
	bayesian_ranking DESC;


-- ############################################################
-- QUERY 2: Movies per Decade & Genre
-- Objective: Count movies produced per decade and genre to
--            identify industry trends and cycles.
-- Logic: Derives decade from start year, explodes genre array,
--        groups and counts.
-- ############################################################

SELECT
	(b.startyear - (b.startyear % 10))::text || 's' AS decade,
	g AS genre,
	COUNT(*) AS movies_produced
FROM title_basics b
JOIN us_display_title us ON us.titleid = b.tconst
CROSS JOIN LATERAL UNNEST(string_to_array(b.genres, ',')) AS g
WHERE b.startyear IS NOT NULL
GROUP BY decade, genre
ORDER BY 
	movies_produced DESC;


-- ############################################################
-- QUERY 3: Movie Length Trends
-- Objective: Analyze how runtime evolves over time (distribution).
-- Logic: Aggregates avg, stddev, and quartiles by year, filtering
--        for years with >500 movies for robustness.
-- ############################################################

SELECT
	b.startyear AS year,
	COUNT(*) AS n_movies,
	ROUND(AVG(b.runtimeminutes), 2) AS average_length,
	ROUND(STDDEV_SAMP(b.runtimeminutes), 2) AS std_minutes_length,
	ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY b.runtimeminutes)::numeric, 2) AS q1_minutes_length,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.runtimeminutes)::numeric, 2) AS q2_minutes_length,
	ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY b.runtimeminutes)::numeric, 2) AS q3_minutes_length
FROM title_basics b
JOIN us_display_title us ON us.titleid = b.tconst
WHERE b.startyear IS NOT NULL AND b.runtimeminutes IS NOT NULL
GROUP BY year
HAVING COUNT(*) > 500
ORDER BY 
	year DESC;


-- ############################################################
-- QUERY 4: Genre Affinity
-- Objective: Find genre pairs that often co-occur in the same movie.
-- Logic: Explodes genres per title, self-joins to form pairs,
--        counts co-occurrences, orders by frequency.
-- ############################################################

WITH exploded AS (
SELECT
	b.tconst,
    b.startyear,
    unnest(string_to_array(b.genres, ',')) AS genre
FROM title_basics b
JOIN us_display_title us ON us.titleid = b.tconst
WHERE b.genres IS NOT NULL
),

pairs AS (
SELECT
	LEAST(e1.genre, e2.genre) AS genre_1,
    GREATEST(e1.genre, e2.genre) AS genre_2,
    e1.tconst,
    e1.startyear
FROM exploded e1
JOIN exploded e2 ON e1.tconst = e2.tconst
	AND e1.genre  < e2.genre      -- avoids (A,B) & (B,A) and self-pairs (A,A)
)

SELECT
	genre_1,
	genre_2,
	COUNT(*) AS titles_with_both_genres
FROM pairs
GROUP BY genre_1, genre_2
ORDER BY 
	titles_with_both_genres DESC;


-- ############################################################
-- QUERY 5: Director Consistency
-- Objective: Identify directors with consistent quality across their filmography.
-- Logic: For each director, compute a log-weighted average of movie ratings:
--            w_avg = sum( ln(votes) * rating ) / sum( ln(votes) )
--        Using ln(votes) dampens the dominance of mega-hit films (very high vote counts),
--        yielding a more balanced view than a simple average or a linear vote weighting.
--        Also show the simple average for reference.
-- ############################################################

WITH dir_titles AS (                           
SELECT 
	DISTINCT p.tconst, 
	p.nconst
FROM title_principals p
JOIN us_display_title us ON us.titleid = p.tconst
WHERE p.category = 'director'
),

rated AS (                                  
SELECT 
	d.nconst, 
	d.tconst, 
	r.averagerating, 
	r.numvotes
FROM dir_titles d
JOIN title_ratings r ON r.tconst = d.tconst
WHERE 
	r.averagerating IS NOT NULL
	AND r.numvotes > 1
)

SELECT
	n.primaryname AS director,
	COUNT(DISTINCT r.tconst) AS n_movies,
	SUM(r.numvotes) AS n_votes,
	ROUND((SUM(LN(r.numvotes) * r.averagerating)::numeric) / SUM(LN(r.numvotes))::numeric, 2) AS w_avg_rating,
	ROUND(AVG(r.averagerating)::numeric, 2) AS simple_avg         
FROM rated r
JOIN name_basics n ON n.nconst = r.nconst
GROUP BY n.primaryname
HAVING COUNT(DISTINCT r.tconst) >= 3        
ORDER BY 
	n_votes DESC, 
	n_movies DESC;


-- ############################################################
-- QUERY 6: Actor–Actor Pairs
-- Objective: Detect frequent actor collaborations.
-- Logic: Builds actor pairs per title (self-join on principals),
--        counts distinct films together, filters for >=3.
-- ############################################################

WITH cast_us AS (                   
SELECT 
	DISTINCT p.tconst, 
	p.nconst
FROM title_principals p
JOIN us_display_title us ON us.titleid = p.tconst
WHERE p.category IN ('actor','actress')        
),

pairs AS ( 
SELECT
	LEAST(a1.nconst, a2.nconst)  AS nconst1,    
    GREATEST(a1.nconst, a2.nconst) AS nconst2,
    a1.tconst
FROM cast_us a1
JOIN cast_us a2 ON a1.tconst = a2.tconst
	AND a1.nconst < a2.nconst                -- avoids (A,B) & (B,A) and self-pairs (A,A)
)

SELECT                                   
	n1.primaryname AS actor1,
	n2.primaryname AS actor2,
	COUNT(DISTINCT p.tconst) AS films_together
FROM pairs p
JOIN name_basics n1 ON n1.nconst = p.nconst1
JOIN name_basics n2 ON n2.nconst = p.nconst2
GROUP BY n1.primaryname, n2.primaryname
HAVING COUNT(DISTINCT p.tconst) >= 3       
ORDER BY 
	films_together DESC, 
	actor1, 
	actor2;


