-- ============================================================
-- FOOTBALL MATCH ANALYTICS
-- PostgreSQL
--
-- Основные SQL-запросы + дополнительные аналитические кейсы.
-- Скриншоты результатов находятся в sql/images/.
-- Для каждого доступного результата указан прямой URL на файл изображения.
-- ============================================================

-- ============================================================
-- 1. Где забивают больше — лиги или кубки?
-- ============================================================

SELECT
    league_name,
    country,
    ROUND(AVG(m.home_score + m.away_score), 2) AS avg_score
FROM leagues l
JOIN matches m ON m.league_id = l.id
GROUP BY league_name, country
ORDER BY avg_score DESC;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/01_avg_goals_by_league.png

-- ============================================================
-- 2. Топ-10 стадионов по средней посещаемости
-- ============================================================

SELECT
    s.stadium_name,
    l.country,
    ROUND(AVG(m.attendance), 0) AS avg_attendance
FROM leagues l
JOIN matches m ON m.league_id = l.id
JOIN stadiums s ON s.id = m.stadium_id
GROUP BY l.country, s.stadium_name
ORDER BY avg_attendance DESC NULLS LAST
LIMIT 10;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/03_top_stadiums_attendance.png


-- ============================================================
-- 3. Win rate команд с учётом дома/гостях
-- ============================================================

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
        SUM(
            CASE
                WHEN m.home_score = m.away_score
                THEN 1 ELSE 0
            END
        ) AS draws,
        SUM(
            CASE
                WHEN (m.home_score < m.away_score AND ms.is_home = TRUE)
                  OR (m.home_score > m.away_score AND ms.is_home = FALSE)
                THEN 1 ELSE 0
            END
        ) AS lose,
        COUNT(*) AS total_matches
    FROM matches m
    JOIN match_team_stats ms ON ms.match_id = m.id
    JOIN teams t ON ms.team_id = t.id
    GROUP BY t.team_name
)
SELECT
    tr.team_name,
    tr.total_matches,
    tr.wins,
    tr.draws,
    tr.lose,
    ROUND(
        (tr.wins::numeric / (tr.wins + tr.draws + tr.lose)),
        2
    ) AS win_rate
FROM team_result tr
WHERE total_matches > 50
ORDER BY win_rate DESC;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/04_winrate_by_team.png


-- ============================================================
-- 4. Кто эффективнее своего xG?
-- ============================================================

WITH xg AS (
    SELECT
        t.team_name,
        AVG(ms.expected_goals_xg) AS avg_xg,
        AVG(
            CASE
                WHEN ms.is_home = TRUE THEN m.home_score
                ELSE m.away_score
            END
        ) AS avg_score
    FROM match_team_stats ms
    JOIN teams t ON t.id = ms.team_id
    JOIN matches m ON m.id = ms.match_id
    GROUP BY t.team_name
),
ranking AS (
    SELECT
        xg.team_name,
        ROUND(xg.avg_xg, 2) AS avg_xg,
        ROUND(xg.avg_score, 2) AS avg_score,
        ROUND(xg.avg_score - xg.avg_xg, 2) AS delta,
        RANK() OVER (
            ORDER BY xg.avg_score - xg.avg_xg ASC NULLS LAST
        ) AS team_rank_over,
        RANK() OVER (
            ORDER BY xg.avg_score - xg.avg_xg DESC NULLS LAST
        ) AS team_rank_under
    FROM xg
)
SELECT
    r.team_name,
    r.avg_xg,
    r.avg_score,
    r.delta,
    r.team_rank_over,
    r.team_rank_under
FROM ranking r
WHERE r.team_rank_over <= 5
   OR r.team_rank_under <= 5;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/07_xg_over_underperformers.png


-- ============================================================
-- 5. Топ-5 сезонов по красным карточкам с pivot
-- ============================================================

WITH red_card_stats AS (
    SELECT
        m.season_year,
        SUM(
            CASE WHEN l.league_name = 'Ligue-1'
                 THEN ms.red_cards ELSE 0 END
        ) AS rc_ligue_1,
        SUM(
            CASE WHEN l.league_name = 'Bundesliga'
                 THEN ms.red_cards ELSE 0 END
        ) AS rc_bundesliga,
        SUM(
            CASE WHEN l.league_name = 'Laliga'
                 THEN ms.red_cards ELSE 0 END
        ) AS rc_laliga,
        SUM(
            CASE WHEN l.league_name = 'Serie-a'
                 THEN ms.red_cards ELSE 0 END
        ) AS rc_serie_a,
        SUM(
            CASE WHEN l.league_name = 'Premier-league'
                 THEN ms.red_cards ELSE 0 END
        ) AS rc_apl,
        SPLIT_PART(m.season_year, '/', 1)::integer AS date_year
    FROM match_team_stats ms
    JOIN matches m ON m.id = ms.match_id
    JOIN leagues l ON l.id = m.league_id
    GROUP BY m.season_year
)
SELECT
    rcs.season_year,
    rc_ligue_1,
    rc_bundesliga,
    rc_laliga,
    rc_serie_a,
    rc_apl
FROM red_card_stats rcs
ORDER BY (
    rc_ligue_1
    + rc_bundesliga
    + rc_laliga
    + rc_serie_a
    + rc_apl
) DESC
LIMIT 5;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/09_red_cards_pivot.png


-- ============================================================
-- 6. Текущая форма команд — последние 5 матчей
-- ============================================================

WITH winrate AS (
    SELECT
        t.team_name,
        SUM(
            CASE
                WHEN (ms.is_home = TRUE AND m.home_score > m.away_score)
                  OR (ms.is_home = FALSE AND m.home_score < m.away_score)
                THEN 1 ELSE 0
            END
        ) AS wins,
        SUM(
            CASE
                WHEN m.home_score = m.away_score
                THEN 1 ELSE 0
            END
        ) AS draws,
        SUM(
            CASE
                WHEN (ms.is_home = TRUE AND m.home_score < m.away_score)
                  OR (ms.is_home = FALSE AND m.home_score > m.away_score)
                THEN 1 ELSE 0
            END
        ) AS lose,
        MAKE_DATE(
            SPLIT_PART(
                m.season_year,
                '/',
                CASE WHEN m.date_month >= 8 THEN 1 ELSE 2 END
            )::integer,
            m.date_month,
            m.date_day
        ) AS match_date
    FROM match_team_stats ms
    JOIN teams t ON t.id = ms.team_id
    JOIN matches m ON m.id = ms.match_id
    GROUP BY t.team_name, m.id, match_date
),
numbers AS (
    SELECT
        w.team_name,
        w.wins,
        w.draws,
        w.lose,
        w.match_date,
        ROW_NUMBER() OVER (
            PARTITION BY w.team_name
            ORDER BY w.match_date DESC
        ) AS num
    FROM winrate w
)
SELECT
    n.team_name,
    SUM(n.wins) AS team_win
FROM numbers n
WHERE num <= 5
GROUP BY n.team_name
ORDER BY team_win DESC
LIMIT 10;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/10_current_form.png

-- ============================================================
-- 7. Г1. Реальность домашнего преимущества
-- ============================================================

WITH home_winrate AS (
    SELECT
        l.league_name,
        CASE
            WHEN m.home_score > m.away_score THEN 1
            ELSE 0
        END AS home_win
    FROM match_team_stats ms
    JOIN matches m ON m.id = ms.match_id
    JOIN leagues l ON l.id = m.league_id
    WHERE ms.is_home = TRUE
)
SELECT
    hw.league_name,
    ROUND(SUM(hw.home_win)::numeric / COUNT(*), 2) AS winrate,
    COUNT(*) AS total_matches
FROM home_winrate hw
GROUP BY hw.league_name
HAVING COUNT(*) > 2000
ORDER BY winrate DESC;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/11_home_advantage_by_league.png


-- ============================================================
-- 8. Г2. Посещаемость и домашняя победа CORR + REGR_SLOPE + REGR_R2
-- ============================================================

SELECT
    CORR(
        (m.home_score > m.away_score)::integer,
        m.attendance
    ) AS corr_home_win,
    REGR_SLOPE(
        (m.home_score > m.away_score)::integer,
        m.attendance
    ) * 1000 AS slope,
    REGR_R2(
        (m.home_score > m.away_score)::integer,
        m.attendance
    ) AS corr_2
FROM matches m
WHERE m.attendance IS NOT NULL;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/12_attendance_correlation.png


-- ============================================================
-- 9. Г3. Самые частые пары соперников
-- ============================================================

WITH pair_matches AS (
    SELECT
        LEAST(m.home_team_id, m.away_team_id) AS team_1_id,
        GREATEST(m.home_team_id, m.away_team_id) AS team_2_id,
        COUNT(*) AS total_matches
    FROM matches m
    GROUP BY
        LEAST(m.home_team_id, m.away_team_id),
        GREATEST(m.home_team_id, m.away_team_id)
)
SELECT
    t1.team_name AS team_1,
    t2.team_name AS team_2,
    pm.total_matches
FROM pair_matches pm
JOIN teams t1 ON t1.id = pm.team_1_id
JOIN teams t2 ON t2.id = pm.team_2_id
ORDER BY pm.total_matches DESC
LIMIT 10;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/13_most_frequent_derbies.png


-- ============================================================
-- 10. Г4. Динамика результативности лиг по сезонам LAG()
-- ============================================================

WITH goals AS (
    SELECT
        l.league_name,
        m.season_year,
        SUM(m.home_score + m.away_score) AS total_goals,
        COUNT(m.id) AS total_matches
    FROM matches m
    JOIN leagues l ON l.id = m.league_id
    GROUP BY l.league_name, m.season_year
    ORDER BY m.season_year
),
per_match AS (
    SELECT
        g.league_name,
        g.season_year,
        ROUND(
            total_goals::numeric / total_matches,
            2
        ) AS goals_per_match
    FROM goals g
),
nums AS (
    SELECT
        pm.league_name,
        pm.season_year,
        pm.goals_per_match,
        LAG(
            goals_per_match,
            1
        ) OVER (
            PARTITION BY pm.league_name
            ORDER BY pm.season_year
        ) AS lages
    FROM per_match pm
)
SELECT
    n.league_name,
    n.season_year,
    n.goals_per_match,
    n.lages,
    n.goals_per_match - n.lages AS delta,
    CASE
        WHEN n.lages IS NOT NULL AND n.lages > 0
        THEN ROUND(
            ((n.goals_per_match - n.lages) / n.lages) * 100,
            2
        )::text || '%'
        ELSE NULL
    END AS perc
FROM nums n
ORDER BY n.league_name, n.season_year;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/16_goals_trend_by_season.png


-- ============================================================
-- 11. Г5. Влияние красных карточек на win rate
-- ============================================================

WITH rc_stats AS (
    SELECT
        l.league_name,
        m.id AS match_id,
        m.home_team_id,
        m.away_team_id,
        m.home_score,
        m.away_score,
        home.red_cards AS home_rc,
        away.red_cards AS away_rc
    FROM matches m
    JOIN leagues l ON l.id = m.league_id
    JOIN match_team_stats home
        ON m.id = home.match_id
       AND m.home_team_id = home.team_id
    JOIN match_team_stats away
        ON m.id = away.match_id
       AND m.away_team_id = away.team_id
),
wining AS (
    SELECT
        rc.league_name,
        rc.home_rc AS own_rc,
        rc.away_rc AS opp_rc,
        CASE
            WHEN rc.home_score > rc.away_score THEN 1
            ELSE 0
        END AS wins
    FROM rc_stats rc

    UNION ALL

    SELECT
        rc.league_name,
        rc.away_rc AS own_rc,
        rc.home_rc AS opp_rc,
        CASE
            WHEN rc.home_score < rc.away_score THEN 1
            ELSE 0
        END AS wins
    FROM rc_stats rc
)
SELECT
    w.league_name,
    COUNT(
        CASE WHEN w.own_rc > 0 THEN 1 END
    ) AS match_rc,
    ROUND(
        AVG(CASE WHEN w.own_rc > 0 THEN w.wins END),
        2
    ) AS winrate_rc,
    COUNT(
        CASE
            WHEN w.own_rc = 0 OR w.own_rc IS NULL
            THEN 1
        END
    ) AS match_without_rc,
    ROUND(
        AVG(
            CASE
                WHEN w.own_rc = 0 OR w.own_rc IS NULL
                THEN w.wins
            END
        ),
        2
    ) AS winrate_without_rc,
    ROUND(
        AVG(
            CASE
                WHEN w.own_rc = 0 OR w.own_rc IS NULL
                THEN w.wins
            END
        )
        -
        AVG(
            CASE
                WHEN w.own_rc > 0
                THEN w.wins
            END
        ),
        2
    ) AS drop_wr
FROM wining w
GROUP BY w.league_name
HAVING COUNT(
    CASE WHEN w.own_rc > 0 THEN 1 END
) != 0
ORDER BY drop_wr DESC;

-- Скриншот:
-- https://github.com/KirdiankinAD/football-analytics-sql-python-tableau/blob/main/sql/images/17_red_cards_vs_winrate.png


-- ============================================================
-- END
-- ============================================================
