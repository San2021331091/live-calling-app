ALTER TABLE calls
    DROP CONSTRAINT IF EXISTS calls_status_check;

ALTER TABLE calls
    ADD CONSTRAINT calls_status_check
    CHECK (status IN ('started', 'active', 'missed', 'ended'));
