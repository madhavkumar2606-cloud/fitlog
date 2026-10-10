# FitLog

An Android app that tracks your workouts and your food together, turns your progress into a game,
and lets you compete with friends.

## Download

**[Download the latest FitLog.apk](../../releases/latest/download/FitLog.apk)**

To install it:
1. Open the downloaded file on your Android phone.
2. If asked, allow your browser or file manager to install unknown apps.
3. If Play Protect says the app is unrecognised, tap **More details → Install anyway**.
   (It shows this for any app not from the Play Store.)

## Features

**Train**
- Routines (starter Push / Pull / Legs included) with a live logger, rest timer,
  your numbers from last time, and suggestions for when to add weight.
- A summary after every workout with XP earned, new personal records and badges.

**Eat**
- Food log by meal, with built-in Indian and gym staples, online search through
  Open Food Facts, and custom foods.
- Maintenance calories that start from a formula, then learn your real number from your data.
- Training-day and rest-day calorie targets, and protein targets based on bodyweight.

**Level up**
- XP for workouts, personal records, weigh-ins and logging.
- Three daily quests that adapt to training and rest days, with a bonus for finishing all three.
- Levels, titles, 14 badges and daily streaks.
- A weekly report with a score out of 100 and plain-language advice.

**Compete**
- Accounts with email or Google sign-in, and a public profile with a username.
- Add friends by username and compete on a weekly XP leaderboard that resets every Monday.
- Friend profiles with head-to-head comparisons. Friends never see your food or weight.

**See your progress**
- Interactive charts: strength, weekly volume, muscle balance, body weight trend,
  calories and macro split, plus an activity heatmap.

## Built with

Flutter, SQLite (sqflite) for on-device data, Supabase (Postgres + Auth) for accounts and
friends, and fl_chart. See [SETUP.md](SETUP.md) to run it yourself.
