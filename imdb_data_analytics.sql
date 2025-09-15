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
a lower ordering value since the combination titleid/ordering is the Primary Key of title_akas table
*/


-- 1) Top Films - Bayesian Rating

with stats as( 
select avg(r.averagerating) as global_mean,
percentile_cont(0.8) within group (order by r.numvotes) as p80_nr_votes
from us_display_title us
join title_ratings r on r.tconst=us.titleid
)

select us.titleid,
us.title,
r.numvotes,
r.averagerating as original_rating,
round(((r.numvotes / (r.numvotes + s.p80_nr_votes)) * r.averagerating + (s.p80_nr_votes / (r.numvotes + s.p80_nr_votes)) * s.global_mean)::numeric, 2) as bayesian_rating
from us_display_title us
join title_ratings r on r.tconst=us.titleid
cross join stats s
order by bayesian_rating desc


-- 2) Top Films per Decade and Genre





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
