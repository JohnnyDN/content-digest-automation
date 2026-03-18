-- public.digests definition

-- Drop table

-- DROP TABLE public.digests;

CREATE TABLE public.digests (
	id serial4 NOT NULL,
	run_date timestamptz DEFAULT now() NOT NULL,
	period_start timestamptz NULL,
	period_end timestamptz NULL,
	full_markdown text NULL,
	linkedin_post_text text NULL,
	video_url text NULL,
	created_at timestamptz DEFAULT now() NULL,
	published_at timestamptz NULL,
	linkedin_url text NULL,
	dominant_topic text NULL,
	topic_category text NULL,
	style_palette jsonb NULL,
	CONSTRAINT digests_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_digests_run_date ON public.digests USING btree (run_date);


-- public.infographic_styles definition

-- Drop table

-- DROP TABLE public.infographic_styles;

CREATE TABLE public.infographic_styles (
	id serial4 NOT NULL,
	topic_category text NOT NULL,
	base_prompt text NOT NULL,
	primary_color text NULL,
	secondary_color text NULL,
	accent_color text NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT infographic_styles_pkey PRIMARY KEY (id),
	CONSTRAINT infographic_styles_topic_category_key UNIQUE (topic_category)
);


-- public.logs definition

-- Drop table

-- DROP TABLE public.logs;

CREATE TABLE public.logs (
	id serial4 NOT NULL,
	"timestamp" timestamptz DEFAULT now() NULL,
	topic text NULL,
	workflow_id int4 NULL,
	"event" text NULL,
	status text NULL,
	details jsonb NULL,
	CONSTRAINT logs_pkey PRIMARY KEY (id)
);


-- public.sources definition

-- Drop table

-- DROP TABLE public.sources;

CREATE TABLE public.sources (
	id serial4 NOT NULL,
	"name" text NOT NULL,
	"type" text NOT NULL,
	url text NOT NULL,
	"language" text NOT NULL,
	created_at timestamptz DEFAULT now() NULL,
	is_active bool DEFAULT true NOT NULL,
	topic text NULL,
	cycle_order int4 DEFAULT 0 NULL,
	CONSTRAINT sources_pkey PRIMARY KEY (id),
	CONSTRAINT sources_url_unique UNIQUE (url)
);


-- public.items definition

-- Drop table

-- DROP TABLE public.items;

CREATE TABLE public.items (
	id serial4 NOT NULL,
	source_id int4 NOT NULL,
	title text NOT NULL,
	url text NOT NULL,
	published_at timestamptz NULL,
	raw_content text NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT items_pkey PRIMARY KEY (id),
	CONSTRAINT items_url_key UNIQUE (url),
	CONSTRAINT items_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE CASCADE
);
CREATE INDEX idx_items_published_at ON public.items USING btree (published_at);


-- public.item_enriched definition

-- Drop table

-- DROP TABLE public.item_enriched;

CREATE TABLE public.item_enriched (
	id serial4 NOT NULL,
	item_id int4 NOT NULL,
	"language" text NULL,
	category text NULL,
	tags jsonb NULL,
	short_summary text NULL,
	detailed_summary text NULL,
	importance_score numeric NULL,
	virality_score numeric NULL,
	created_at timestamptz DEFAULT now() NULL,
	CONSTRAINT item_enriched_pkey PRIMARY KEY (id),
	CONSTRAINT item_enriched_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE
);
CREATE INDEX idx_item_enriched_item_id ON public.item_enriched USING btree (item_id);
CREATE UNIQUE INDEX item_enriched_item_id_key ON public.item_enriched USING btree (item_id);

-- Additional performance indexes
CREATE INDEX IF NOT EXISTS idx_items_source_id ON public.items(source_id);
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON public.logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_workflow_event ON public.logs(workflow_id, event);
CREATE INDEX IF NOT EXISTS idx_sources_topic_active ON public.sources(topic, is_active);