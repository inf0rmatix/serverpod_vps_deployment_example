BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "serverpod_session_log" ADD COLUMN "userId" text;

--
-- MIGRATION VERSION FOR vps_deployment
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('vps_deployment', '20260202154103957', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260202154103957', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20251208110333922-v3-0-0', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20251208110333922-v3-0-0', "timestamp" = now();


COMMIT;
