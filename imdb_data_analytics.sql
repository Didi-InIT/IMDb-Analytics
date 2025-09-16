DROP VIEW IF EXISTS us_display_title;
CREATE VIEW us_display_title AS
SELECT DISTINCT ON (titleid)
       titleid, ordering, title
FROM title_akas
WHERE region = 'US' 
ORDER BY titleid,
         CASE WHEN types='imdbDisplay' THEN 0 ELSE 1 END,
         ordering

/* 
View to select all the movies for the region US, with a distinct prioritizing imdbDisplay as display type and
a lower ordering value since the combination titleid/ordering is the Primary Key of title_akas table.
*/


-- 1) Top Films - Bayesian Rating

WITH stats AS( 
SELECT AVG(r.averagerating) AS global_mean,
PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY r.numvotes) AS p80_nr_votes
FROM us_display_title us
JOIN title_ratings r ON r.tconst=us.titleid
)

SELECT us.titleid,
us.title,
r.numvotes,
r.averagerating AS original_rating,
round(((r.numvotes / (r.numvotes + s.p80_nr_votes)) * r.averagerating + (s.p80_nr_votes / (r.numvotes + s.p80_nr_votes)) * s.global_mean)::numeric, 2) as bayesian_rating
FROM us_display_title us
JOIN title_ratings r ON r.tconst=us.titleid
CROSS JOIN stats s
ORDER BY bayesian_rating DESC

/* 
The Bayesian Rating takes into account the number of votes that a given movie received to balance out it´s rating, and thus, 
for example, preventing movies that got a 10.0 rating with only two votes from being at the top of the scoreboard. 
*/


-- 2) Top Films per Decade/Genre

SELECT
  (b.startyear - (b.startyear % 10))::text || 's' as decade,
  g AS genre,
  COUNT(*) AS movies_produced
FROM title_basics b
CROSS JOIN LATERAL UNNEST(string_to_array(b.genres, ',')) AS g
WHERE b.startyear IS NOT NULL
GROUP BY decade, genre
ORDER BY movies_produced DESC


-- 3) Film Length Trends 




-- 4) Top Films - Bayesian Rating

-- 5) Top Films - Bayesian Rating

-- 6) Top Films - Bayesian Rating

-- 7) Top Films - Bayesian Rating

-- 8) Top Films - Bayesian Rating

-- 9) Top Films - Bayesian Rating

-- 10) Top Films - Bayesian Rating

-- 11) Top Films - Bayesian Rating

-- 12) Top Films - Bayesian Rating
