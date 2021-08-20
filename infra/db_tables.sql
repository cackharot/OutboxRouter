CREATE SEQUENCE IF NOT EXISTS public.event_sequence
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 9223372036854775807
	START 1
	CACHE 1
	NO CYCLE;

CREATE SEQUENCE IF NOT EXISTS public.outbox_sequence
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 9223372036854775807
	START 1
	CACHE 1
	NO CYCLE;

CREATE TABLE IF NOT EXISTS public.domain_event_entry (
	global_index bigint NOT NULL DEFAULT nextval('event_sequence'),
	aggregate_identifier varchar(255) NOT NULL,
	sequence_number bigint NOT NULL,
	"type" varchar(255) NOT NULL,
	event_identifier varchar(255) NOT NULL,
	payload_type varchar(255) NOT NULL,
	payload bytea NULL,
	metadata bytea NULL,
	"timestamp" varchar(255) NOT NULL,
	PRIMARY KEY (global_index, event_identifier),
	UNIQUE (event_identifier)
) PARTITION BY HASH (event_identifier);
CREATE UNIQUE INDEX IF NOT EXISTS domain_event_entry_event_identifier_idx ON public.domain_event_entry (event_identifier);
CREATE INDEX IF NOT EXISTS domain_event_entry_aggregate_identifier_idx ON public.domain_event_entry (aggregate_identifier,sequence_number,"timestamp");
-- CREATE UNIQUE INDEX IF NOT EXISTS domain_event_entry_aggregate_identifier_idx ON public.domain_event_entry (aggregate_identifier,sequence_number);

CREATE TABLE IF NOT EXISTS public.outbox (
	global_index bigint NOT NULL DEFAULT nextval('outbox_sequence'),
	"type" varchar(255) NOT NULL,
	event_identifier varchar(255) NOT NULL,
	payload_type varchar(255) NOT NULL,
	payload bytea NULL,
	metadata bytea NULL,
	"timestamp" varchar(255) NOT NULL,
	CONSTRAINT outbox_global_index_pk PRIMARY KEY (global_index),
	CONSTRAINT outbox_event_identifier_ux UNIQUE (event_identifier)
);

CREATE TABLE IF NOT EXISTS public.token_entry (
	processor_name varchar(255) NOT NULL,
	segment int NOT NULL,
	"token" bytea NULL,
	token_type varchar(255) NULL,
	"owner" varchar(255) NULL,
	"timestamp" varchar(255) NOT NULL,
	CONSTRAINT token_entry_pk PRIMARY KEY (processor_name,segment)
);
