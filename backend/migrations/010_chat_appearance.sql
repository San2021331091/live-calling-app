ALTER TABLE chats ADD COLUMN IF NOT EXISTS avatar_url TEXT NOT NULL DEFAULT '';
ALTER TABLE chats ADD COLUMN IF NOT EXISTS theme TEXT NOT NULL DEFAULT 'classic'
    CHECK (theme IN ('classic', 'ocean', 'rose', 'lavender', 'sand'));
ALTER TABLE chat_members ADD COLUMN IF NOT EXISTS theme TEXT NOT NULL DEFAULT ''
    CHECK (theme IN ('', 'classic', 'ocean', 'rose', 'lavender', 'sand'));
