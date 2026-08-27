## Примеры запросов

### Средний счёт по лигам и кубкам

```sql
SELECT
    l.league_name,
    l.country,
    ROUND(AVG(m.home_score + m.away_score), 2) AS avg_goals
FROM leagues l
JOIN matches m
    ON m.league_id = l.id
GROUP BY
    l.league_name,
    l.country
ORDER BY avg_goals DESC;
```

Кубки заметно результативнее лиг: DFB‑Pokal — 3.61 гола за матч, FA Cup — 3.21, против 2.5–2.94 у топ‑5 лиг.

![Средний счёт по лигам](images/01_avg_goals_by_league.png)

### Win rate команд с фильтром по выборке

```sql
WITH team_result AS (
    SELECT
        t.team_name,
        SUM(
            CASE
                WHEN (m.home_score > m.away_score AND ms.is_home = TRUE)
                  OR (m.home_score < m.away_score AND ms.is_home = FALSE)
                THEN 1 ELSE 0
            END
        ) AS wins,
        COUNT(*) AS total_matches
    FROM matches m
    JOIN match_team_stats ms
        ON ms.match_id = m.id
    JOIN teams t
        ON t.id = ms.team_id
    GROUP BY t.team_name
)
SELECT
    team_name,
    total_matches,
    ROUND(wins::numeric / total_matches, 2) AS win_rate
FROM team_result
WHERE total_matches > 50
ORDER BY win_rate DESC;
```

После отсечения команд с < 50 матчей лидирует Bayern Munich — 0.71 (654 победы из 924).

![Win rate по командам](images/04_winrate_by_team.png)

### Влияние красных карточек на win rate (упрощённо)

```sql
WITH home_winrate AS (
    SELECT
        l.league_name,
        CASE WHEN m.home_score > m.away_score THEN 1 ELSE 0 END AS home_win
    FROM match_team_stats ms
    JOIN matches m
        ON m.id = ms.match_id
    JOIN leagues l
        ON l.id = m.league_id
    WHERE ms.is_home = TRUE
)
SELECT
    league_name,
    ROUND(SUM(home_win)::numeric / COUNT(*), 2) AS winrate,
    COUNT(*) AS total_matches
FROM home_winrate
GROUP BY league_name
HAVING COUNT(*) > 2000
ORDER BY winrate DESC;
```

После фильтра по размеру выборки все турниры укладываются в 0.43–0.47 — разброс ~4 п.п.

![Домашнее преимущество по лигам](images/11_home_advantage_by_league.png)

Полные версии запросов (включая анализ red cards vs win rate, xG over/underperformance, pivot по сезонам и динамику голов через `LAG`) — в [`sql/queries.sql`](sql/queries.sql).

---

## Проверка гипотез

### Г1. Домашнее преимущество одинаково во всех лигах?

**Вывод:** отклонена в сильной форме. После фильтра малых выборок win rate хозяев ≈ 0.43–0.47 во всех крупных турнирах.

![Домашнее преимущество по лигам](images/11_home_advantage_by_league.png)

### Г2. Посещаемость влияет на исход матча?

**Вывод:** отклонена в сильной форме. Корреляция ~0.12, \(R^2 = 0.014\) — посещаемость объясняет ~1.4% разброса исходов.

![Корреляция посещаемости и результата](images/12_attendance_correlation.png)

### Г3. Есть ли пары команд с аномально частыми встречами?

**Вывод:** подтверждена, особенно для Италии. 7 из топ‑10 пар — итальянские (AS Roma – Inter, 63 встречи).

![Самые частые пары соперников](images/13_most_frequent_derbies.png)

### Г4. Есть ли «инфляция голов» со временем?

**Вывод:** отклонена. На примере турецкой 1‑lig результативность колеблется ±20% без устойчивого тренда.

![Динамика результативности по сезонам](images/16_goals_trend_by_season.png)

### Г5. Красная карточка снижает шанс на победу?

**Вывод:** подтверждена, эффект универсален. Падение win rate фиксируется во всех 16 турнирах; в АПЛ почти вдвое (0.38 → 0.20).

![Влияние красных карточек на win rate](images/17_red_cards_vs_winrate.png)
