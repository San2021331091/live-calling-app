ALTER TABLE ai_turns ADD COLUMN mode TEXT NOT NULL DEFAULT 'chat'
 CHECK (mode IN ('chat','photos','videos','web'));
ALTER TABLE ai_turns ADD COLUMN results JSONB NOT NULL DEFAULT '[]'::jsonb;
