# Impas TT – система за записване на часове

## 1. Supabase (база данни и вход)
1. Влез в supabase.com, направи безплатен акаунт и **New project** (запази паролата на базата).
2. **SQL Editor → New query**, постави цялото съдържание на `supabase.sql` и натисни **Run**.
3. **Project Settings → API**: копирай **Project URL** и **anon public key**.
4. Отвори `index.html` и замени `PASTE_PROJECT_URL` и `PASTE_ANON_PUBLIC_KEY` (в реда под "SETTINGS").

## 2. Първи админ
1. **Authentication → Users → Add user**: въведи имейл и парола (ще е входът ти).
2. Копирай ID-то на потребителя и в **SQL Editor** пусни:
   `insert into profiles(id,name,role) values('ТВОЕТО-ID','Име','admin');`
3. За мениджър или служител: същото, с `'manager'` или `'staff'`.

## 3. GitHub Pages
1. В github.com направи **публично** хранилище (напр. `impas-tt`) и качи съдържанието на папката (`index.html` и `assets`).
2. **Settings → Pages → Branch: main, папка / (root) → Save**.
3. След минута сайтът е на `https://ПОТРЕБИТЕЛ.github.io/impas-tt/`.

Ключът `anon` е предвиден да е публичен. Защитата е в правилата на базата (RLS) от `supabase.sql`.

## Какво още не е направено
Имейли и напомнания, ръчно добавяне на час, редакция на услуги и график от панела, блокиране на дни, статистики, създаване на служители от сайта, автоматично изтриване след 15 месеца.
