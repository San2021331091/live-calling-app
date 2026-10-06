ALTER TABLE call_signals
    ADD COLUMN IF NOT EXISTS sequence BIGSERIAL;

CREATE UNIQUE INDEX IF NOT EXISTS call_signals_sequence_idx
    ON call_signals (sequence);
