BEGIN;
CREATE TABLE "contact_article" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "sujet" varchar(100) NOT NULL, "auteur" varchar(42) NOT NULL, "message" text NULL);

COMMIT;
