CREATE TABLE ai_turns (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id UUID NOT NULL,
    prompt TEXT NOT NULL CHECK (char_length(prompt) BETWEEN 1 AND 4000),
    reply TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','complete','failed')),
    error TEXT NOT NULL DEFAULT '',
    attempts INTEGER NOT NULL DEFAULT 0,
    lease_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, client_id)
);
CREATE UNIQUE INDEX ai_one_pending_per_user ON ai_turns(user_id)
    WHERE status IN ('queued','processing');
CREATE INDEX ai_turns_user_history ON ai_turns(user_id,id DESC);
CREATE INDEX ai_turns_queue ON ai_turns(status,lease_until,id);
