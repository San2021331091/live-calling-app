ALTER TABLE chats ADD COLUMN IF NOT EXISTS community_type TEXT;
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_kind_check;
ALTER TABLE chats DROP CONSTRAINT IF EXISTS chats_check;

ALTER TABLE chats
    ADD CONSTRAINT chats_kind_check
        CHECK (kind IN ('direct', 'group', 'community')),
    ADD CONSTRAINT chats_type_fields_check
        CHECK (
            (kind = 'direct' AND title IS NULL AND direct_key IS NOT NULL AND community_type IS NULL) OR
            (kind = 'group' AND title IS NOT NULL AND direct_key IS NULL AND community_type IS NULL) OR
            (kind = 'community' AND title IS NOT NULL AND direct_key IS NULL
                AND community_type IS NOT NULL
                AND char_length(community_type) BETWEEN 1 AND 40)
        );
