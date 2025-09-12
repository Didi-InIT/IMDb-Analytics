-- 1) Top Films - Bayesian Rating



SELECT distinct on (a.titleid) a.titleid, a.ordering, a.title, a.region, a.types, a.isoriginaltitle, r.tconst, r.averagerating, r.numvotes
from title_akas a
left join title_ratings r on a.titleid=r.tconst
where a.region = 'US'
order by a.titleid, case when a.types = 'imdbDisplay' then 0 else 1 end, a.ordering




-- filters to always include from title_akas: region = 'US' 