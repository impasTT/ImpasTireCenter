-- IMPAS TT: paste in Supabase > SQL Editor > Run
create table services(id serial primary key, name_bg text, name_en text, minutes int, resource text check(resource in('tires','geometry')), tires_choice bool default false, active bool default true, sort int default 0);
insert into services(name_bg,name_en,minutes,resource,tires_choice,sort) values
('Смяна на гуми','Tire change',20,'tires',true,1),('Ремонт на гума','Tire repair',20,'tires',true,2),
('3D геометрия – преден мост','3D alignment – front axle',20,'geometry',false,3),('3D геометрия – преден и заден мост','3D alignment – front and rear axle',35,'geometry',false,4);

create table settings(key text primary key, value int);
insert into settings values('max_days',30),('min_hours',12),('strike_limit',5),('keep_months',15),('cap_tires',2),('cap_geometry',1);

create table work_hours(dow int primary key, open_t time, close_t time, closed bool default false); -- 0=Sunday
insert into work_hours values(1,'08:00','18:00',false),(2,'08:00','18:00',false),(3,'08:00','18:00',false),(4,'08:00','18:00',false),(5,'08:00','18:00',false),(6,'08:00','14:00',false),(0,null,null,true);

create table blocked_days(id serial primary key, day date, from_t time, to_t time, note text); -- whole day if from_t is null

create table bookings(id uuid primary key default gen_random_uuid(), token uuid unique default gen_random_uuid(), service_id int references services, tires int, day date, slot time,
 name text, phone text, email text, car text, comment text, status text default 'booked' check(status in('booked','done','noshow','cancelled')), created timestamptz default now());

create table clients(email text primary key, phone text, strikes int default 0, blocked bool default false);
create table profiles(id uuid primary key references auth.users on delete cascade, name text, role text check(role in('admin','manager','staff')));

create function my_role() returns text language sql stable security definer as $$ select role from profiles where id=auth.uid() $$;

-- strikes: cancellation or no-show = 1 point, 5th blocks the client
create function add_strike() returns trigger language plpgsql security definer as $$
begin
 if new.status in('cancelled','noshow') and old.status='booked' then
  insert into clients(email,phone,strikes) values(lower(new.email),new.phone,1)
  on conflict(email) do update set strikes=clients.strikes+1, phone=new.phone;
  update clients set blocked=true where email=lower(new.email) and strikes>=(select value from settings where key='strike_limit');
 end if; return new; end $$;
create trigger t_strike after update of status on bookings for each row execute function add_strike();

create function cap(r text) returns int language sql stable as $$ select value from settings where key='cap_'||r $$;

create function get_slots(p_day date, p_service int) returns table(slot time, free int) language plpgsql security definer as $$
declare r text; w work_hours; t time; mh int; md int;
begin
 select resource into r from services where id=p_service;
 select value into mh from settings where key='min_hours'; select value into md from settings where key='max_days';
 if p_day > (now() at time zone 'Europe/Sofia')::date + md then return; end if;
 select * into w from work_hours where dow=extract(dow from p_day);
 if w.closed or w.open_t is null then return; end if;
 if exists(select 1 from blocked_days where day=p_day and from_t is null) then return; end if;
 t:=w.open_t;
 while t < w.close_t loop
  if (p_day+t) at time zone 'Europe/Sofia' >= now()+make_interval(hours=>mh)
   and not exists(select 1 from blocked_days b where b.day=p_day and t>=b.from_t and t<b.to_t) then
   slot:=t; free:=cap(r)-(select count(*) from bookings b join services s on s.id=b.service_id where b.day=p_day and b.slot=t and s.resource=r and b.status in('booked','done'));
   if free>0 then return next; end if;
  end if; t:=t+interval '1 hour';
 end loop;
end $$;

create function book(p_service int, p_tires int, p_day date, p_slot time, p_name text, p_phone text, p_email text, p_car text, p_comment text) returns json language plpgsql security definer as $$
declare tk uuid;
begin
 if exists(select 1 from clients where blocked and (email=lower(p_email) or phone=p_phone)) then return json_build_object('error','blocked'); end if;
 perform pg_advisory_xact_lock(extract(epoch from p_day)::bigint);
 if not exists(select 1 from get_slots(p_day,p_service) where slot=p_slot) then return json_build_object('error','taken'); end if;
 insert into bookings(service_id,tires,day,slot,name,phone,email,car,comment) values(p_service,p_tires,p_day,p_slot,p_name,p_phone,lower(p_email),p_car,p_comment) returning token into tk;
 return json_build_object('token',tk);
end $$;

create function get_booking(p_token uuid) returns json language sql security definer as $$
 select row_to_json(x) from(select b.day,b.slot,b.status,b.name,b.service_id,s.name_bg,s.name_en from bookings b join services s on s.id=b.service_id where token=p_token) x $$;

create function cancel_booking(p_token uuid) returns void language sql security definer as $$ update bookings set status='cancelled' where token=p_token and status='booked' $$;

create function move_booking(p_token uuid, p_day date, p_slot time) returns json language plpgsql security definer as $$
declare sid int;
begin
 select service_id into sid from bookings where token=p_token and status='booked';
 if sid is null then return json_build_object('error','none'); end if;
 perform pg_advisory_xact_lock(extract(epoch from p_day)::bigint);
 if not exists(select 1 from get_slots(p_day,sid) where slot=p_slot) then return json_build_object('error','taken'); end if;
 update bookings set day=p_day, slot=p_slot where token=p_token; return json_build_object('ok',true);
end $$;

-- security: public can only call the functions; staff read/write by role
alter table services enable row level security; alter table settings enable row level security; alter table work_hours enable row level security;
alter table blocked_days enable row level security; alter table bookings enable row level security; alter table clients enable row level security; alter table profiles enable row level security;
create policy s_read on services for select using(true);
create policy s_edit on services for all using(my_role() in('admin','manager')) with check(my_role() in('admin','manager'));
create policy st_read on settings for select using(true);
create policy st_edit on settings for all using(my_role() in('admin','manager')) with check(my_role() in('admin','manager'));
create policy w_read on work_hours for select using(true);
create policy w_edit on work_hours for all using(my_role() in('admin','manager')) with check(my_role() in('admin','manager'));
create policy bd_read on blocked_days for select using(true);
create policy bd_edit on blocked_days for all using(my_role() in('admin','manager')) with check(my_role() in('admin','manager'));
create policy b_read on bookings for select using(my_role() is not null);
create policy b_upd on bookings for update using(my_role() is not null);
create policy c_read on clients for select using(my_role() in('admin','manager'));
create policy c_upd on clients for update using(my_role() in('admin','manager'));
create policy p_read on profiles for select using(id=auth.uid() or my_role()='admin');
create policy p_edit on profiles for all using(my_role()='admin') with check(my_role()='admin');
revoke execute on function get_slots,book,get_booking,cancel_booking,move_booking from public;
grant execute on function get_slots,book,get_booking,cancel_booking,move_booking to anon,authenticated;
