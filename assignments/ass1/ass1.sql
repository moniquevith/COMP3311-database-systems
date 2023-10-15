-- COMP3311 23T3 Assignment 1

---- Q1

create or replace view Q1(state,nbreweries) 
as
select 
    l.region as state, 
    count(b.located_in) as nbreweries
from breweries b
    join locations l on l.id=b.located_in
where l.country='Australia'
group by l.region
; 

---- Q2

create or replace view Q2(style,min_abv,max_abv)
as
select 
    name as style, 
    min_abv, 
    max_abv 
from styles 
where max_abv - min_abv = (select max(max_abv - min_abv) from styles)
;

---- Q3

create or replace view Q3(style,lo_abv,hi_abv,min_abv,max_abv)
as
select
    S.name as style,
    min(B.ABV) as lo_abv,
    max(B.ABV) as hi_abv,
    S.min_abv,
    S.max_abv
from Styles S  
inner join Beers B on S.id = B.style
group by
    S.name, S.min_abv, S.max_abv
having
    S.min_abv != S.max_abv and (min(B.ABV) < S.min_abv or max(B.ABV) > S.max_abv)
;

---- Q4

create or replace view Q4(brewery,rating) 
as
select brewery, max(r) as rating 
from 
    (select 
        b.name as brewery,
        avg(y.rating)::NUMERIC(3,1) as r
    from breweries b
    join brewed_by bb on bb.brewery=b.id
    join beers y on bb.beer=y.id
    where y.rating is not NULL
    group by b.name
    having count(y.rating) >= 5) as subquery
group by subquery.brewery, subquery.r
order by r DESC
LIMIT 1
;

---- Q5

create or replace function
    Q5(pattern text) returns table(beer text, container text, std_drinks numeric(3,1))
AS $$
    select
        b.name as beer,
        case
            when b.sold_in = 'bottle' then b.volume || 'ml bottle'
            when b.sold_in = 'can' then b.volume || 'ml can'
            when b.sold_in = 'growler' then 'growler'
            when b.sold_in = 'keg' then 'keg'
            else 'unknown'
        end 
        as container,
        round((b.volume * b.ABV * 0.0008)::numeric, 1) as std_drinks
    from Beers b
    where b.name ILIKE '%' || pattern || '%';
$$ 
language sql ;

---- Q6

create or replace function
   Q6(pattern text) returns table(country text, first integer, nbeers integer, rating numeric)
as $$
    select 
        L.country as country,
        min(Y.brewed) as first, 
        count(Y.name) as nbeers, 
        cast(avg(Y.rating) as NUMERIC(3,1)) as rating
    from locations L 
    join breweries B on B.located_in=L.id
    join brewed_by BB on BB.brewery=B.id
    join beers Y on Y.id=BB.beer
    where L.country ILIKE '%' || pattern || '%'
    group by L.country;
$$
language sql ;

---- Q7

create or replace function
   Q7(_beerID integer) returns text
as $$
declare 
    beer_name text;
    ingredients_list text = '';
    result_text text; 
    ingred_info record;  
begin
    select name into beer_name
    from beers 
    where id=_beerID;

    if beer_name is NULL then 
        result_text := 'No such beer ' || '(' || _beerID || ')';
    else 
        for ingred_info in (select i.name as ingredient_name, i.itype as ingredient_type
                from Contains c
                join Ingredients i on c.ingredient = i.id
                where c.beer = _beerID
                order by i.name)
        loop
            ingredients_list := ingredients_list || E'\n    ' || ingred_info.ingredient_name || ' (' || ingred_info.ingredient_type || ')';
        end loop;

        if length(ingredients_list) = 0 then
            ingredients_list := '  no ingredients recorded';
            result_text := '"' || beer_name || '"' || E'\n' || ingredients_list;
        else 
            result_text := '"' || beer_name || '"' || E'\n' || '  contains:' || ingredients_list;
        end if;
    end if; 

    return result_text;
end;
$$
language plpgsql ;

---- Q8

drop type if exists BeerHops cascade;
create type BeerHops as (beer text, brewery text, hops text);

create or replace function
   Q8(pattern text) RETURNS SETOF BeerHops
as $$
declare 
    beer_data_row record;
    hops text = '';
    h record;
    is_first boolean;
begin 
    for beer_data_row in (select b.name as beer, array_agg(DISTINCT y.name) as brewery 
        from beers b 
        join brewed_by bb on bb.beer = b.id
        join breweries y on y.id = bb.brewery
        where b.name ILIKE '%' || pattern || '%'
        group by b.name
        order by b.name) 
    loop 
        hops := '';
        -- get names of hops for beer and put into hops variable
        is_first = true;
        for h in (select i.name as hop_name
            from beers b
            join contains c on c.beer = b.id
            join ingredients i on i.id = c.ingredient
            where b.name = beer_data_row.beer and i.itype = 'hop'
            group by i.name
            order by i.name)
        loop
            if is_first then
                hops := h.hop_name;
                is_first := false;
            else
                hops := hops || ',' || h.hop_name;
            end if;
        end loop;

        -- check is any hops exist 
        if length(hops) = 0 then 
            hops := 'no hops recorded';
        end if; 

        --  add current row iteration as BeerHops type to return function (accumulate set of tuples)
        return next (beer_data_row.beer, array_to_string(beer_data_row.brewery, '+'), hops); 
    end loop; 
    return; 
end; 
$$
language plpgsql ;