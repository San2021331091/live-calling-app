CREATE TABLE IF NOT EXISTS statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_url TEXT NOT NULL CHECK (char_length(media_url) BETWEEN 1 AND 2048),
    media_type TEXT NOT NULL CHECK (media_type IN ('image', 'video')),
    caption TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS statuses_user_created_idx
    ON statuses (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS statuses_expiry_idx
    ON statuses (expires_at);
