CREATE TABLE visits (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hostname    TEXT        NOT NULL,
    visited_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
