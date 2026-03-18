-- Initial reference data for AI Content Digest System
-- Run this after 01_schema.sql

-- =========================
-- Sources
-- =========================

INSERT INTO public.sources (name, type, url, language, is_active, topic, cycle_order) VALUES
    ('VentureBeat AI', 'RSS', 'https://venturebeat.com/category/ai/feed/', 'en', false, 'AI', 1),
    ('AI4Business', 'RSS', 'https://www.ai4business.it/feed/', 'it', false, 'AI', 1),
    ('Avant Music News', 'RSS', 'https://avantmusicnews.com/feed', 'en', false, 'Music', 3),
    ('ScienceDaily', 'RSS', 'https://www.sciencedaily.com/rss/all.xml', 'en', false, 'Science', 4),
    ('Le Scienze', 'RSS', 'https://www.lescienze.it/comunicati-stampa/rss', 'it', false, 'Science', 4),
    ('CNBC', 'RSS', 'https://www.cnbc.com/id/100003114/device/rss/rss.html', 'en', false, 'Finance', 2),
    ('Il Sole 24 Ore Economia', 'RSS', 'https://www.ilsole24ore.com/rss/economia.xml', 'it', false, 'Finance', 2),
    ('Billboard IT', 'RSS', 'https://billboard.it/feed/', 'it', false, 'Music', 3);

-- Reset sequence
SELECT setval('sources_id_seq', (SELECT MAX(id) FROM sources));

-- =========================
-- Infographic Styles
-- =========================

INSERT INTO public.infographic_styles (topic_category, base_prompt, primary_color, secondary_color, accent_color) VALUES
    ('AI', 'Professional tech infographic for AI workforce and business trends targeting recruiters, talent leaders, and business managers. Modern, data-driven aesthetic.', '#6366F1', '#818CF8', '#3B82F6'),
    ('Finance', 'Professional financial infographic for market trends, economic insights, and investment analysis targeting investors, advisors, and business executives. Clean, analytical aesthetic.', '#10B981', '#34D399', '#059669'),
    ('Music', 'Creative music industry infographic for business trends, artist news, and streaming insights targeting industry professionals, artists, and managers. Vibrant, energetic aesthetic.', '#EC4899', '#F472B6', '#DB2777'),
    ('Science', 'Educational science infographic for research breakthroughs and discoveries targeting educated professionals and science enthusiasts. Clear, trustworthy aesthetic.', '#3B82F6', '#60A5FA', '#2563EB');

-- Reset sequence
SELECT setval('infographic_styles_id_seq', (SELECT MAX(id) FROM infographic_styles));