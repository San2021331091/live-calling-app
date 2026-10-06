CREATE TABLE IF NOT EXISTS status_views (
    status_id UUID NOT NULL REFERENCES statuses(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (status_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS status_views_viewer_idx
    ON status_views (viewer_id, viewed_at DESC);
