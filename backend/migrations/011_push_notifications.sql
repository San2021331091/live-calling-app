CREATE TABLE push_devices (
    installation_id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX push_devices_user_idx ON push_devices(user_id);

-- An outbox keeps notification retries atomic with saving the message/call.
CREATE TABLE push_jobs (
    id BIGSERIAL PRIMARY KEY,
    installation_id UUID NOT NULL REFERENCES push_devices(installation_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    call_id UUID REFERENCES calls(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts INTEGER NOT NULL DEFAULT 0,
    CHECK ((message_id IS NULL) <> (call_id IS NULL))
);
CREATE INDEX push_jobs_available_idx ON push_jobs(available_at);
CREATE INDEX push_jobs_device_idx ON push_jobs(installation_id);

CREATE FUNCTION queue_message_push() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO push_jobs(installation_id, user_id, message_id, expires_at)
    SELECT d.installation_id, d.user_id, NEW.id, now() + interval '5 minutes'
    FROM chat_members m JOIN push_devices d ON d.user_id = m.user_id
    WHERE m.chat_id = NEW.chat_id AND m.user_id <> NEW.sender_id AND NOT m.muted
      AND d.updated_at > now() - interval '30 days';
    RETURN NEW;
END;
$$;
CREATE TRIGGER message_push AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION queue_message_push();

CREATE FUNCTION queue_call_push() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'started' THEN
        INSERT INTO push_jobs(installation_id, user_id, call_id, expires_at)
        SELECT installation_id, user_id, NEW.id, NEW.started_at + interval '2 minutes'
        FROM push_devices WHERE user_id = NEW.callee_id
          AND updated_at > now() - interval '30 days';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER call_push AFTER INSERT ON calls
FOR EACH ROW EXECUTE FUNCTION queue_call_push();
