--
-- PostgreSQL database dump
--

-- Dumped from database version 9.4.1
-- Dumped by pg_dump version 9.4.2
-- Started on 2015-05-31 15:40:04

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 7 (class 2615 OID 1753933)
-- Name: pgagent; Type: SCHEMA; Schema: -; Owner: bpprsodytbgwip
--

CREATE SCHEMA pgagent;


ALTER SCHEMA pgagent OWNER TO bpprsodytbgwip;

--
-- TOC entry 3137 (class 0 OID 0)
-- Dependencies: 7
-- Name: SCHEMA pgagent; Type: COMMENT; Schema: -; Owner: bpprsodytbgwip
--

COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';


--
-- TOC entry 205 (class 3079 OID 12749)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 3140 (class 0 OID 0)
-- Dependencies: 205
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 224 (class 1255 OID 1754102)
-- Name: pga_exception_trigger(); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pga_exception_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_jobid int4 := 0;

BEGIN

     IF TG_OP = 'DELETE' THEN

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = OLD.jexscid;

        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN OLD;
    ELSE

        SELECT INTO v_jobid jscjobid FROM pgagent.pga_schedule WHERE jscid = NEW.jexscid;

        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid = v_jobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_exception_trigger() OWNER TO bpprsodytbgwip;

--
-- TOC entry 3141 (class 0 OID 0)
-- Dependencies: 224
-- Name: FUNCTION pga_exception_trigger(); Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON FUNCTION pga_exception_trigger() IS 'Update the job''s next run time whenever an exception changes';


--
-- TOC entry 221 (class 1255 OID 1754097)
-- Name: pga_is_leap_year(smallint); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pga_is_leap_year(smallint) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    IF $1 % 4 != 0 THEN
        RETURN FALSE;
    END IF;

    IF $1 % 100 != 0 THEN
        RETURN TRUE;
    END IF;

    RETURN $1 % 400 = 0;
END;
$_$;


ALTER FUNCTION pgagent.pga_is_leap_year(smallint) OWNER TO bpprsodytbgwip;

--
-- TOC entry 3142 (class 0 OID 0)
-- Dependencies: 221
-- Name: FUNCTION pga_is_leap_year(smallint); Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON FUNCTION pga_is_leap_year(smallint) IS 'Returns TRUE if $1 is a leap year';


--
-- TOC entry 222 (class 1255 OID 1754098)
-- Name: pga_job_trigger(); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pga_job_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.jobenabled THEN
        IF NEW.jobnextrun IS NULL THEN
             SELECT INTO NEW.jobnextrun
                    MIN(pgagent.pga_next_schedule(jscid, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths))
               FROM pgagent.pga_schedule
              WHERE jscenabled AND jscjobid=OLD.jobid;
        END IF;
    ELSE
        NEW.jobnextrun := NULL;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION pgagent.pga_job_trigger() OWNER TO bpprsodytbgwip;

--
-- TOC entry 3143 (class 0 OID 0)
-- Dependencies: 222
-- Name: FUNCTION pga_job_trigger(); Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON FUNCTION pga_job_trigger() IS 'Update the job''s next run time.';


--
-- TOC entry 220 (class 1255 OID 1754095)
-- Name: pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $_$
DECLARE
    jscid           ALIAS FOR $1;
    jscstart        ALIAS FOR $2;
    jscend          ALIAS FOR $3;
    jscminutes      ALIAS FOR $4;
    jschours        ALIAS FOR $5;
    jscweekdays     ALIAS FOR $6;
    jscmonthdays    ALIAS FOR $7;
    jscmonths       ALIAS FOR $8;

    nextrun         timestamp := '1970-01-01 00:00:00-00';
    runafter        timestamp := '1970-01-01 00:00:00-00';

    bingo            bool := FALSE;
    gotit            bool := FALSE;
    foundval        bool := FALSE;
    daytweak        bool := FALSE;
    minutetweak        bool := FALSE;

    i                int2 := 0;
    d                int2 := 0;

    nextminute        int2 := 0;
    nexthour        int2 := 0;
    nextday            int2 := 0;
    nextmonth       int2 := 0;
    nextyear        int2 := 0;


BEGIN
    -- No valid start date has been specified
    IF jscstart IS NULL THEN RETURN NULL; END IF;

    -- The schedule is past its end date
    IF jscend IS NOT NULL AND jscend < now() THEN RETURN NULL; END IF;

    -- Get the time to find the next run after. It will just be the later of
    -- now() + 1m and the start date for the time being, however, we might want to
    -- do more complex things using this value in the future.
    IF date_trunc('MINUTE', jscstart) > date_trunc('MINUTE', (now() + '1 Minute'::interval)) THEN
        runafter := date_trunc('MINUTE', jscstart);
    ELSE
        runafter := date_trunc('MINUTE', (now() + '1 Minute'::interval));
    END IF;

    --
    -- Enter a loop, generating next run timestamps until we find one
    -- that falls on the required weekday, and is not matched by an exception
    --

    WHILE bingo = FALSE LOOP

        --
        -- Get the next run year
        --
        nextyear := date_part('YEAR', runafter);

        --
        -- Get the next run month
        --
        nextmonth := date_part('MONTH', runafter);
        gotit := FALSE;
        FOR i IN (nextmonth) .. 12 LOOP
            IF jscmonths[i] = TRUE THEN
                nextmonth := i;
                gotit := TRUE;
                foundval := TRUE;
                EXIT;
            END IF;
        END LOOP;
        IF gotit = FALSE THEN
            FOR i IN 1 .. (nextmonth - 1) LOOP
                IF jscmonths[i] = TRUE THEN
                    nextmonth := i;

                    -- Wrap into next year
                    nextyear := nextyear + 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
           END LOOP;
        END IF;

        --
        -- Get the next run day
        --
        -- If the year, or month have incremented, get the lowest day,
        -- otherwise look for the next day matching or after today.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter)) THEN
            nextday := 1;
            FOR i IN 1 .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextday := date_part('DAY', runafter);
            gotit := FALSE;
            FOR i IN nextday .. 32 LOOP
                IF jscmonthdays[i] = TRUE THEN
                    nextday := i;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. (nextday - 1) LOOP
                    IF jscmonthdays[i] = TRUE THEN
                        nextday := i;

                        -- Wrap into next month
                        IF nextmonth = 12 THEN
                            nextyear := nextyear + 1;
                            nextmonth := 1;
                        ELSE
                            nextmonth := nextmonth + 1;
                        END IF;
                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Was the last day flag selected?
        IF nextday = 32 THEN
            IF nextmonth = 1 THEN
                nextday := 31;
            ELSIF nextmonth = 2 THEN
                IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                    nextday := 29;
                ELSE
                    nextday := 28;
                END IF;
            ELSIF nextmonth = 3 THEN
                nextday := 31;
            ELSIF nextmonth = 4 THEN
                nextday := 30;
            ELSIF nextmonth = 5 THEN
                nextday := 31;
            ELSIF nextmonth = 6 THEN
                nextday := 30;
            ELSIF nextmonth = 7 THEN
                nextday := 31;
            ELSIF nextmonth = 8 THEN
                nextday := 31;
            ELSIF nextmonth = 9 THEN
                nextday := 30;
            ELSIF nextmonth = 10 THEN
                nextday := 31;
            ELSIF nextmonth = 11 THEN
                nextday := 30;
            ELSIF nextmonth = 12 THEN
                nextday := 31;
            END IF;
        END IF;

        --
        -- Get the next run hour
        --
        -- If the year, month or day have incremented, get the lowest hour,
        -- otherwise look for the next hour matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR daytweak = TRUE) THEN
            nexthour := 0;
            FOR i IN 1 .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nexthour := date_part('HOUR', runafter);
            gotit := FALSE;
            FOR i IN (nexthour + 1) .. 24 LOOP
                IF jschours[i] = TRUE THEN
                    nexthour := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nexthour LOOP
                    IF jschours[i] = TRUE THEN
                        nexthour := i - 1;

                        -- Wrap into next month
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nextday = d THEN
                            nextday := 1;
                            IF nextmonth = 12 THEN
                                nextyear := nextyear + 1;
                                nextmonth := 1;
                            ELSE
                                nextmonth := nextmonth + 1;
                            END IF;
                        ELSE
                            nextday := nextday + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        --
        -- Get the next run minute
        --
        -- If the year, month day or hour have incremented, get the lowest minute,
        -- otherwise look for the next minute matching or after the current one.
        IF (nextyear > date_part('YEAR', runafter) OR nextmonth > date_part('MONTH', runafter) OR nextday > date_part('DAY', runafter) OR nexthour > date_part('HOUR', runafter) OR daytweak = TRUE) THEN
            nextminute := 0;
            IF minutetweak = TRUE THEN
        d := 1;
            ELSE
        d := date_part('YEAR', runafter)::int2;
            END IF;
            FOR i IN d .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        ELSE
            nextminute := date_part('MINUTE', runafter);
            gotit := FALSE;
            FOR i IN (nextminute + 1) .. 60 LOOP
                IF jscminutes[i] = TRUE THEN
                    nextminute := i - 1;
                    gotit := TRUE;
                    foundval := TRUE;
                    EXIT;
                END IF;
            END LOOP;
            IF gotit = FALSE THEN
                FOR i IN 1 .. nextminute LOOP
                    IF jscminutes[i] = TRUE THEN
                        nextminute := i - 1;

                        -- Wrap into next hour
                        IF (nextmonth = 1 OR nextmonth = 3 OR nextmonth = 5 OR nextmonth = 7 OR nextmonth = 8 OR nextmonth = 10 OR nextmonth = 12) THEN
                            d = 31;
                        ELSIF (nextmonth = 4 OR nextmonth = 6 OR nextmonth = 9 OR nextmonth = 11) THEN
                            d = 30;
                        ELSE
                            IF pgagent.pga_is_leap_year(nextyear) = TRUE THEN
                                d := 29;
                            ELSE
                                d := 28;
                            END IF;
                        END IF;

                        IF nexthour = 23 THEN
                            nexthour = 0;
                            IF nextday = d THEN
                                nextday := 1;
                                IF nextmonth = 12 THEN
                                    nextyear := nextyear + 1;
                                    nextmonth := 1;
                                ELSE
                                    nextmonth := nextmonth + 1;
                                END IF;
                            ELSE
                                nextday := nextday + 1;
                            END IF;
                        ELSE
                            nexthour := nexthour + 1;
                        END IF;

                        gotit := TRUE;
                        foundval := TRUE;
                        EXIT;
                    END IF;
                END LOOP;
            END IF;
        END IF;

        -- Build the result, and check it is not the same as runafter - this may
        -- happen if all array entries are set to false. In this case, add a minute.

        nextrun := (nextyear::varchar || '-'::varchar || nextmonth::varchar || '-' || nextday::varchar || ' ' || nexthour::varchar || ':' || nextminute::varchar)::timestamptz;

        IF nextrun = runafter AND foundval = FALSE THEN
                nextrun := nextrun + INTERVAL '1 Minute';
        END IF;

        -- If the result is past the end date, exit.
        IF nextrun > jscend THEN
            RETURN NULL;
        END IF;

        -- Check to ensure that the nextrun time is actually still valid. Its
        -- possible that wrapped values may have carried the nextrun onto an
        -- invalid time or date.
        IF ((jscminutes = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscminutes[date_part('MINUTE', nextrun) + 1] = TRUE) AND
            (jschours = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jschours[date_part('HOUR', nextrun) + 1] = TRUE) AND
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonthdays[date_part('DAY', nextrun)] = TRUE OR
            (jscmonthdays = '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,t}' AND
             ((date_part('MONTH', nextrun) IN (1,3,5,7,8,10,12) AND date_part('DAY', nextrun) = 31) OR
              (date_part('MONTH', nextrun) IN (4,6,9,11) AND date_part('DAY', nextrun) = 30) OR
              (date_part('MONTH', nextrun) = 2 AND ((pgagent.pga_is_leap_year(date_part('DAY', nextrun)::int2) AND date_part('DAY', nextrun) = 29) OR date_part('DAY', nextrun) = 28))))) AND
            (jscmonths = '{f,f,f,f,f,f,f,f,f,f,f,f}' OR jscmonths[date_part('MONTH', nextrun)] = TRUE)) THEN


            -- Now, check to see if the nextrun time found is a) on an acceptable
            -- weekday, and b) not matched by an exception. If not, set
            -- runafter = nextrun and try again.

            -- Check for a wildcard weekday
            gotit := FALSE;
            FOR i IN 1 .. 7 LOOP
                IF jscweekdays[i] = TRUE THEN
                    gotit := TRUE;
                    EXIT;
                END IF;
            END LOOP;

            -- OK, is the correct weekday selected, or a wildcard?
            IF (jscweekdays[date_part('DOW', nextrun) + 1] = TRUE OR gotit = FALSE) THEN

                -- Check for exceptions
                SELECT INTO d jexid FROM pgagent.pga_exception WHERE jexscid = jscid AND ((jexdate = nextrun::date AND jextime = nextrun::time) OR (jexdate = nextrun::date AND jextime IS NULL) OR (jexdate IS NULL AND jextime = nextrun::time));
                IF FOUND THEN
                    -- Nuts - found an exception. Increment the time and try again
                    runafter := nextrun + INTERVAL '1 Minute';
                    bingo := FALSE;
                    minutetweak := TRUE;
            daytweak := FALSE;
                ELSE
                    bingo := TRUE;
                END IF;
            ELSE
                -- We're on the wrong week day - increment a day and try again.
                runafter := nextrun + INTERVAL '1 Day';
                bingo := FALSE;
                minutetweak := FALSE;
                daytweak := TRUE;
            END IF;

        ELSE
            runafter := nextrun + INTERVAL '1 Minute';
            bingo := FALSE;
            minutetweak := TRUE;
        daytweak := FALSE;
        END IF;

    END LOOP;

    RETURN nextrun;
END;
$_$;


ALTER FUNCTION pgagent.pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) OWNER TO bpprsodytbgwip;

--
-- TOC entry 3144 (class 0 OID 0)
-- Dependencies: 220
-- Name: FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]); Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON FUNCTION pga_next_schedule(integer, timestamp with time zone, timestamp with time zone, boolean[], boolean[], boolean[], boolean[], boolean[]) IS 'Calculates the next runtime for a given schedule';


--
-- TOC entry 223 (class 1255 OID 1754100)
-- Name: pga_schedule_trigger(); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pga_schedule_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- update pga_job from remaining schedules
        -- the actual calculation of jobnextrun will be performed in the trigger
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=OLD.jscjobid;
        RETURN OLD;
    ELSE
        UPDATE pgagent.pga_job
           SET jobnextrun = NULL
         WHERE jobenabled AND jobid=NEW.jscjobid;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION pgagent.pga_schedule_trigger() OWNER TO bpprsodytbgwip;

--
-- TOC entry 3145 (class 0 OID 0)
-- Dependencies: 223
-- Name: FUNCTION pga_schedule_trigger(); Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON FUNCTION pga_schedule_trigger() IS 'Update the job''s next run time whenever a schedule changes';


--
-- TOC entry 219 (class 1255 OID 1754094)
-- Name: pgagent_schema_version(); Type: FUNCTION; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE FUNCTION pgagent_schema_version() RETURNS smallint
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- RETURNS PGAGENT MAJOR VERSION
    -- WE WILL CHANGE THE MAJOR VERSION, ONLY IF THERE IS A SCHEMA CHANGE
    RETURN 3;
END;
$$;


ALTER FUNCTION pgagent.pgagent_schema_version() OWNER TO bpprsodytbgwip;

SET search_path = public, pg_catalog;

--
-- TOC entry 218 (class 1255 OID 1753437)
-- Name: clear_contact(); Type: FUNCTION; Schema: public; Owner: bpprsodytbgwip
--

CREATE FUNCTION clear_contact() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	BEGIN 	
		
		DELETE FROM contact_article WHERE lu=True;
	
	RETURN NEW;
	END;
	$$;


ALTER FUNCTION public.clear_contact() OWNER TO bpprsodytbgwip;

--
-- TOC entry 225 (class 1255 OID 1791231)
-- Name: compteur_commentaire(); Type: FUNCTION; Schema: public; Owner: bpprsodytbgwip
--

CREATE FUNCTION compteur_commentaire() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	BEGIN 	
		IF (TG_OP = 'DELETE') THEN
			UPDATE comment_compteur SET compteur=compteur-1 WHERE id=1;
			RETURN NEW;
		ELSIF (TG_OP = 'INSERT') THEN
			UPDATE comment_compteur SET compteur=compteur+1 WHERE id=1;
			RETURN NEW;
		END IF;
	
	RETURN NULL;
	END;
	$$;


ALTER FUNCTION public.compteur_commentaire() OWNER TO bpprsodytbgwip;

SET search_path = pgagent, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 196 (class 1259 OID 1754039)
-- Name: pga_exception; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_exception (
    jexid integer NOT NULL,
    jexscid integer NOT NULL,
    jexdate date,
    jextime time without time zone
);


ALTER TABLE pga_exception OWNER TO bpprsodytbgwip;

--
-- TOC entry 195 (class 1259 OID 1754037)
-- Name: pga_exception_jexid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_exception_jexid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_exception_jexid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3146 (class 0 OID 0)
-- Dependencies: 195
-- Name: pga_exception_jexid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_exception_jexid_seq OWNED BY pga_exception.jexid;


--
-- TOC entry 190 (class 1259 OID 1753957)
-- Name: pga_job; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_job (
    jobid integer NOT NULL,
    jobjclid integer NOT NULL,
    jobname text NOT NULL,
    jobdesc text DEFAULT ''::text NOT NULL,
    jobhostagent text DEFAULT ''::text NOT NULL,
    jobenabled boolean DEFAULT true NOT NULL,
    jobcreated timestamp with time zone DEFAULT now() NOT NULL,
    jobchanged timestamp with time zone DEFAULT now() NOT NULL,
    jobagentid integer,
    jobnextrun timestamp with time zone,
    joblastrun timestamp with time zone
);


ALTER TABLE pga_job OWNER TO bpprsodytbgwip;

--
-- TOC entry 3147 (class 0 OID 0)
-- Dependencies: 190
-- Name: TABLE pga_job; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_job IS 'Job main entry';


--
-- TOC entry 3148 (class 0 OID 0)
-- Dependencies: 190
-- Name: COLUMN pga_job.jobagentid; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_job.jobagentid IS 'Agent that currently executes this job.';


--
-- TOC entry 189 (class 1259 OID 1753955)
-- Name: pga_job_jobid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_job_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_job_jobid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3149 (class 0 OID 0)
-- Dependencies: 189
-- Name: pga_job_jobid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_job_jobid_seq OWNED BY pga_job.jobid;


--
-- TOC entry 186 (class 1259 OID 1753934)
-- Name: pga_jobagent; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_jobagent (
    jagpid integer NOT NULL,
    jaglogintime timestamp with time zone DEFAULT now() NOT NULL,
    jagstation text NOT NULL
);


ALTER TABLE pga_jobagent OWNER TO bpprsodytbgwip;

--
-- TOC entry 3150 (class 0 OID 0)
-- Dependencies: 186
-- Name: TABLE pga_jobagent; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_jobagent IS 'Active job agents';


--
-- TOC entry 188 (class 1259 OID 1753945)
-- Name: pga_jobclass; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_jobclass (
    jclid integer NOT NULL,
    jclname text NOT NULL
);


ALTER TABLE pga_jobclass OWNER TO bpprsodytbgwip;

--
-- TOC entry 3151 (class 0 OID 0)
-- Dependencies: 188
-- Name: TABLE pga_jobclass; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_jobclass IS 'Job classification';


--
-- TOC entry 187 (class 1259 OID 1753943)
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_jobclass_jclid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobclass_jclid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3152 (class 0 OID 0)
-- Dependencies: 187
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_jobclass_jclid_seq OWNED BY pga_jobclass.jclid;


--
-- TOC entry 198 (class 1259 OID 1754054)
-- Name: pga_joblog; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_joblog (
    jlgid integer NOT NULL,
    jlgjobid integer NOT NULL,
    jlgstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jlgstart timestamp with time zone DEFAULT now() NOT NULL,
    jlgduration interval,
    CONSTRAINT pga_joblog_jlgstatus_check CHECK ((jlgstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'f'::bpchar, 'i'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_joblog OWNER TO bpprsodytbgwip;

--
-- TOC entry 3153 (class 0 OID 0)
-- Dependencies: 198
-- Name: TABLE pga_joblog; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_joblog IS 'Job run logs.';


--
-- TOC entry 3154 (class 0 OID 0)
-- Dependencies: 198
-- Name: COLUMN pga_joblog.jlgstatus; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_joblog.jlgstatus IS 'Status of job: r=running, s=successfully finished, f=failed, i=no steps to execute, d=aborted';


--
-- TOC entry 197 (class 1259 OID 1754052)
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_joblog_jlgid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_joblog_jlgid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3155 (class 0 OID 0)
-- Dependencies: 197
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_joblog_jlgid_seq OWNED BY pga_joblog.jlgid;


--
-- TOC entry 192 (class 1259 OID 1753983)
-- Name: pga_jobstep; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_jobstep (
    jstid integer NOT NULL,
    jstjobid integer NOT NULL,
    jstname text NOT NULL,
    jstdesc text DEFAULT ''::text NOT NULL,
    jstenabled boolean DEFAULT true NOT NULL,
    jstkind character(1) NOT NULL,
    jstcode text NOT NULL,
    jstconnstr text DEFAULT ''::text NOT NULL,
    jstdbname name DEFAULT ''::name NOT NULL,
    jstonerror character(1) DEFAULT 'f'::bpchar NOT NULL,
    jscnextrun timestamp with time zone,
    CONSTRAINT pga_jobstep_check CHECK ((((jstconnstr <> ''::text) AND (jstkind = 's'::bpchar)) OR ((jstconnstr = ''::text) AND ((jstkind = 'b'::bpchar) OR (jstdbname <> ''::name))))),
    CONSTRAINT pga_jobstep_check1 CHECK ((((jstdbname <> ''::name) AND (jstkind = 's'::bpchar)) OR ((jstdbname = ''::name) AND ((jstkind = 'b'::bpchar) OR (jstconnstr <> ''::text))))),
    CONSTRAINT pga_jobstep_jstkind_check CHECK ((jstkind = ANY (ARRAY['b'::bpchar, 's'::bpchar]))),
    CONSTRAINT pga_jobstep_jstonerror_check CHECK ((jstonerror = ANY (ARRAY['f'::bpchar, 's'::bpchar, 'i'::bpchar])))
);


ALTER TABLE pga_jobstep OWNER TO bpprsodytbgwip;

--
-- TOC entry 3156 (class 0 OID 0)
-- Dependencies: 192
-- Name: TABLE pga_jobstep; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_jobstep IS 'Job step to be executed';


--
-- TOC entry 3157 (class 0 OID 0)
-- Dependencies: 192
-- Name: COLUMN pga_jobstep.jstkind; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_jobstep.jstkind IS 'Kind of jobstep: s=sql, b=batch';


--
-- TOC entry 3158 (class 0 OID 0)
-- Dependencies: 192
-- Name: COLUMN pga_jobstep.jstonerror; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_jobstep.jstonerror IS 'What to do if step returns an error: f=fail the job, s=mark step as succeeded and continue, i=mark as fail but ignore it and proceed';


--
-- TOC entry 191 (class 1259 OID 1753981)
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_jobstep_jstid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobstep_jstid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3159 (class 0 OID 0)
-- Dependencies: 191
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_jobstep_jstid_seq OWNED BY pga_jobstep.jstid;


--
-- TOC entry 200 (class 1259 OID 1754071)
-- Name: pga_jobsteplog; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_jobsteplog (
    jslid integer NOT NULL,
    jsljlgid integer NOT NULL,
    jsljstid integer NOT NULL,
    jslstatus character(1) DEFAULT 'r'::bpchar NOT NULL,
    jslresult integer,
    jslstart timestamp with time zone DEFAULT now() NOT NULL,
    jslduration interval,
    jsloutput text,
    CONSTRAINT pga_jobsteplog_jslstatus_check CHECK ((jslstatus = ANY (ARRAY['r'::bpchar, 's'::bpchar, 'i'::bpchar, 'f'::bpchar, 'd'::bpchar])))
);


ALTER TABLE pga_jobsteplog OWNER TO bpprsodytbgwip;

--
-- TOC entry 3160 (class 0 OID 0)
-- Dependencies: 200
-- Name: TABLE pga_jobsteplog; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_jobsteplog IS 'Job step run logs.';


--
-- TOC entry 3161 (class 0 OID 0)
-- Dependencies: 200
-- Name: COLUMN pga_jobsteplog.jslstatus; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_jobsteplog.jslstatus IS 'Status of job step: r=running, s=successfully finished,  f=failed stopping job, i=ignored failure, d=aborted';


--
-- TOC entry 3162 (class 0 OID 0)
-- Dependencies: 200
-- Name: COLUMN pga_jobsteplog.jslresult; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON COLUMN pga_jobsteplog.jslresult IS 'Return code of job step';


--
-- TOC entry 199 (class 1259 OID 1754069)
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_jobsteplog_jslid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_jobsteplog_jslid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3163 (class 0 OID 0)
-- Dependencies: 199
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_jobsteplog_jslid_seq OWNED BY pga_jobsteplog.jslid;


--
-- TOC entry 194 (class 1259 OID 1754009)
-- Name: pga_schedule; Type: TABLE; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE pga_schedule (
    jscid integer NOT NULL,
    jscjobid integer NOT NULL,
    jscname text NOT NULL,
    jscdesc text DEFAULT ''::text NOT NULL,
    jscenabled boolean DEFAULT true NOT NULL,
    jscstart timestamp with time zone DEFAULT now() NOT NULL,
    jscend timestamp with time zone,
    jscminutes boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jschours boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscweekdays boolean[] DEFAULT '{f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonthdays boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    jscmonths boolean[] DEFAULT '{f,f,f,f,f,f,f,f,f,f,f,f}'::boolean[] NOT NULL,
    CONSTRAINT pga_schedule_jschours_size CHECK ((array_upper(jschours, 1) = 24)),
    CONSTRAINT pga_schedule_jscminutes_size CHECK ((array_upper(jscminutes, 1) = 60)),
    CONSTRAINT pga_schedule_jscmonthdays_size CHECK ((array_upper(jscmonthdays, 1) = 32)),
    CONSTRAINT pga_schedule_jscmonths_size CHECK ((array_upper(jscmonths, 1) = 12)),
    CONSTRAINT pga_schedule_jscweekdays_size CHECK ((array_upper(jscweekdays, 1) = 7))
);


ALTER TABLE pga_schedule OWNER TO bpprsodytbgwip;

--
-- TOC entry 3164 (class 0 OID 0)
-- Dependencies: 194
-- Name: TABLE pga_schedule; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TABLE pga_schedule IS 'Job schedule exceptions';


--
-- TOC entry 193 (class 1259 OID 1754007)
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE SEQUENCE pga_schedule_jscid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE pga_schedule_jscid_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3165 (class 0 OID 0)
-- Dependencies: 193
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE OWNED BY; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER SEQUENCE pga_schedule_jscid_seq OWNED BY pga_schedule.jscid;


SET search_path = public, pg_catalog;

--
-- TOC entry 183 (class 1259 OID 1727058)
-- Name: comment_comment; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE comment_comment (
    id integer NOT NULL,
    auteur character varying(200) NOT NULL,
    texte text NOT NULL
);


ALTER TABLE comment_comment OWNER TO bpprsodytbgwip;

--
-- TOC entry 182 (class 1259 OID 1727056)
-- Name: comment_comment__new_id_seq1; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE comment_comment__new_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comment_comment__new_id_seq1 OWNER TO bpprsodytbgwip;

--
-- TOC entry 3166 (class 0 OID 0)
-- Dependencies: 182
-- Name: comment_comment__new_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE comment_comment__new_id_seq1 OWNED BY comment_comment.id;


--
-- TOC entry 204 (class 1259 OID 1791455)
-- Name: comment_compteur; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE comment_compteur (
    compteur integer DEFAULT 8 NOT NULL,
    id integer NOT NULL
);


ALTER TABLE comment_compteur OWNER TO bpprsodytbgwip;

--
-- TOC entry 203 (class 1259 OID 1791453)
-- Name: comment_compteur_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE comment_compteur_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE comment_compteur_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3167 (class 0 OID 0)
-- Dependencies: 203
-- Name: comment_compteur_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE comment_compteur_id_seq OWNED BY comment_compteur.id;


--
-- TOC entry 185 (class 1259 OID 1727167)
-- Name: contact_article; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE contact_article (
    id integer NOT NULL,
    sujet character varying(100) NOT NULL,
    auteur character varying(42) NOT NULL,
    message text,
    lu boolean DEFAULT false NOT NULL
);


ALTER TABLE contact_article OWNER TO bpprsodytbgwip;

--
-- TOC entry 184 (class 1259 OID 1727165)
-- Name: contact_article_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE contact_article_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE contact_article_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3168 (class 0 OID 0)
-- Dependencies: 184
-- Name: contact_article_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE contact_article_id_seq OWNED BY contact_article.id;


--
-- TOC entry 202 (class 1259 OID 1788837)
-- Name: vote_citation; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_citation (
    cit character(200),
    id integer NOT NULL,
    auteur character(100)
);


ALTER TABLE vote_citation OWNER TO bpprsodytbgwip;

--
-- TOC entry 201 (class 1259 OID 1788835)
-- Name: vote_citation_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE vote_citation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE vote_citation_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3169 (class 0 OID 0)
-- Dependencies: 201
-- Name: vote_citation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE vote_citation_id_seq OWNED BY vote_citation.id;


--
-- TOC entry 174 (class 1259 OID 1726681)
-- Name: vote_departement; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_departement (
    id integer NOT NULL,
    "NumDep" integer NOT NULL,
    "NomDep" character varying(200) NOT NULL
);


ALTER TABLE vote_departement OWNER TO bpprsodytbgwip;

--
-- TOC entry 173 (class 1259 OID 1726679)
-- Name: vote_departement_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE vote_departement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE vote_departement_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3170 (class 0 OID 0)
-- Dependencies: 173
-- Name: vote_departement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE vote_departement_id_seq OWNED BY vote_departement.id;


--
-- TOC entry 181 (class 1259 OID 1726890)
-- Name: vote_scoredep; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_scoredep (
    id integer NOT NULL,
    "ScoreDep" integer NOT NULL,
    "NumDep_id" integer NOT NULL,
    "VoteDep_id" integer NOT NULL
);


ALTER TABLE vote_scoredep OWNER TO bpprsodytbgwip;

--
-- TOC entry 180 (class 1259 OID 1726888)
-- Name: vote_scoredep__new_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE vote_scoredep__new_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE vote_scoredep__new_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3171 (class 0 OID 0)
-- Dependencies: 180
-- Name: vote_scoredep__new_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE vote_scoredep__new_id_seq OWNED BY vote_scoredep.id;


--
-- TOC entry 179 (class 1259 OID 1726871)
-- Name: vote_votant; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_votant (
    id integer NOT NULL,
    ipvotant character varying(100) NOT NULL
);


ALTER TABLE vote_votant OWNER TO bpprsodytbgwip;

--
-- TOC entry 178 (class 1259 OID 1726869)
-- Name: vote_votant__new_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE vote_votant__new_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE vote_votant__new_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3172 (class 0 OID 0)
-- Dependencies: 178
-- Name: vote_votant__new_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE vote_votant__new_id_seq OWNED BY vote_votant.id;


--
-- TOC entry 175 (class 1259 OID 1726700)
-- Name: vote_vote; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_vote (
    "NumVote" integer NOT NULL,
    "Score" integer NOT NULL,
    "NomVote" character varying(100) NOT NULL,
    "ImgVote" character varying(100) NOT NULL
);


ALTER TABLE vote_vote OWNER TO bpprsodytbgwip;

--
-- TOC entry 177 (class 1259 OID 1726739)
-- Name: vote_voteform; Type: TABLE; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE TABLE vote_voteform (
    id integer NOT NULL,
    "formDep" integer NOT NULL,
    "formVote" integer NOT NULL
);


ALTER TABLE vote_voteform OWNER TO bpprsodytbgwip;

--
-- TOC entry 176 (class 1259 OID 1726737)
-- Name: vote_voteform_id_seq; Type: SEQUENCE; Schema: public; Owner: bpprsodytbgwip
--

CREATE SEQUENCE vote_voteform_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE vote_voteform_id_seq OWNER TO bpprsodytbgwip;

--
-- TOC entry 3173 (class 0 OID 0)
-- Dependencies: 176
-- Name: vote_voteform_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: bpprsodytbgwip
--

ALTER SEQUENCE vote_voteform_id_seq OWNED BY vote_voteform.id;


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 2921 (class 2604 OID 1754042)
-- Name: jexid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_exception ALTER COLUMN jexid SET DEFAULT nextval('pga_exception_jexid_seq'::regclass);


--
-- TOC entry 2891 (class 2604 OID 1753960)
-- Name: jobid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_job ALTER COLUMN jobid SET DEFAULT nextval('pga_job_jobid_seq'::regclass);


--
-- TOC entry 2890 (class 2604 OID 1753948)
-- Name: jclid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobclass ALTER COLUMN jclid SET DEFAULT nextval('pga_jobclass_jclid_seq'::regclass);


--
-- TOC entry 2922 (class 2604 OID 1754057)
-- Name: jlgid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_joblog ALTER COLUMN jlgid SET DEFAULT nextval('pga_joblog_jlgid_seq'::regclass);


--
-- TOC entry 2897 (class 2604 OID 1753986)
-- Name: jstid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobstep ALTER COLUMN jstid SET DEFAULT nextval('pga_jobstep_jstid_seq'::regclass);


--
-- TOC entry 2926 (class 2604 OID 1754074)
-- Name: jslid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobsteplog ALTER COLUMN jslid SET DEFAULT nextval('pga_jobsteplog_jslid_seq'::regclass);


--
-- TOC entry 2907 (class 2604 OID 1754012)
-- Name: jscid; Type: DEFAULT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_schedule ALTER COLUMN jscid SET DEFAULT nextval('pga_schedule_jscid_seq'::regclass);


SET search_path = public, pg_catalog;

--
-- TOC entry 2886 (class 2604 OID 1727061)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY comment_comment ALTER COLUMN id SET DEFAULT nextval('comment_comment__new_id_seq1'::regclass);


--
-- TOC entry 2932 (class 2604 OID 1791459)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY comment_compteur ALTER COLUMN id SET DEFAULT nextval('comment_compteur_id_seq'::regclass);


--
-- TOC entry 2887 (class 2604 OID 1727170)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY contact_article ALTER COLUMN id SET DEFAULT nextval('contact_article_id_seq'::regclass);


--
-- TOC entry 2930 (class 2604 OID 1788840)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_citation ALTER COLUMN id SET DEFAULT nextval('vote_citation_id_seq'::regclass);


--
-- TOC entry 2882 (class 2604 OID 1726684)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_departement ALTER COLUMN id SET DEFAULT nextval('vote_departement_id_seq'::regclass);


--
-- TOC entry 2885 (class 2604 OID 1726893)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_scoredep ALTER COLUMN id SET DEFAULT nextval('vote_scoredep__new_id_seq'::regclass);


--
-- TOC entry 2884 (class 2604 OID 1726874)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_votant ALTER COLUMN id SET DEFAULT nextval('vote_votant__new_id_seq'::regclass);


--
-- TOC entry 2883 (class 2604 OID 1726742)
-- Name: id; Type: DEFAULT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_voteform ALTER COLUMN id SET DEFAULT nextval('vote_voteform_id_seq'::regclass);


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 3123 (class 0 OID 1754039)
-- Dependencies: 196
-- Data for Name: pga_exception; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_exception (jexid, jexscid, jexdate, jextime) FROM stdin;
\.


--
-- TOC entry 3174 (class 0 OID 0)
-- Dependencies: 195
-- Name: pga_exception_jexid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_exception_jexid_seq', 1, false);


--
-- TOC entry 3117 (class 0 OID 1753957)
-- Dependencies: 190
-- Data for Name: pga_job; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM stdin;
\.


--
-- TOC entry 3175 (class 0 OID 0)
-- Dependencies: 189
-- Name: pga_job_jobid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_job_jobid_seq', 1, false);


--
-- TOC entry 3113 (class 0 OID 1753934)
-- Dependencies: 186
-- Data for Name: pga_jobagent; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_jobagent (jagpid, jaglogintime, jagstation) FROM stdin;
\.


--
-- TOC entry 3115 (class 0 OID 1753945)
-- Dependencies: 188
-- Data for Name: pga_jobclass; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_jobclass (jclid, jclname) FROM stdin;
1	Routine Maintenance
2	Data Import
3	Data Export
4	Data Summarisation
5	Miscellaneous
\.


--
-- TOC entry 3176 (class 0 OID 0)
-- Dependencies: 187
-- Name: pga_jobclass_jclid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_jobclass_jclid_seq', 5, true);


--
-- TOC entry 3125 (class 0 OID 1754054)
-- Dependencies: 198
-- Data for Name: pga_joblog; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM stdin;
\.


--
-- TOC entry 3177 (class 0 OID 0)
-- Dependencies: 197
-- Name: pga_joblog_jlgid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_joblog_jlgid_seq', 1, false);


--
-- TOC entry 3119 (class 0 OID 1753983)
-- Dependencies: 192
-- Data for Name: pga_jobstep; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM stdin;
\.


--
-- TOC entry 3178 (class 0 OID 0)
-- Dependencies: 191
-- Name: pga_jobstep_jstid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_jobstep_jstid_seq', 1, false);


--
-- TOC entry 3127 (class 0 OID 1754071)
-- Dependencies: 200
-- Data for Name: pga_jobsteplog; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM stdin;
\.


--
-- TOC entry 3179 (class 0 OID 0)
-- Dependencies: 199
-- Name: pga_jobsteplog_jslid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_jobsteplog_jslid_seq', 1, false);


--
-- TOC entry 3121 (class 0 OID 1754009)
-- Dependencies: 194
-- Data for Name: pga_schedule; Type: TABLE DATA; Schema: pgagent; Owner: bpprsodytbgwip
--

COPY pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM stdin;
\.


--
-- TOC entry 3180 (class 0 OID 0)
-- Dependencies: 193
-- Name: pga_schedule_jscid_seq; Type: SEQUENCE SET; Schema: pgagent; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('pga_schedule_jscid_seq', 1, false);


SET search_path = public, pg_catalog;

--
-- TOC entry 3110 (class 0 OID 1727058)
-- Dependencies: 183
-- Data for Name: comment_comment; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY comment_comment (id, auteur, texte) FROM stdin;
1	bonjour	coucou\r\n
2	second commentaire	coucou
3	Couaafff	Coucou mon ami =)
4	les noces pourpres 	Alors que Robb pense être revenu plus ou moins dans les bonnes grâces de Walder Frey après avoir épousé une autre femme que celle qui lui était promise, il assiste heureux à ce qu'il estime être un bon arrangement. A sa place, c'est Edmure qui va épouser l'une des filles Frey et, en plus, la plus jolie. Ouf... Le mariage se déroule sous les meilleurs auspices, le vin coule à flot, Robb et sa Talisa sont heureux comme des pinçons en pensant à l'enfant qui va arriver. Enfin du bonheur ! Mais, après que les deux époux soient partis faire ce qu'ils avaient à faire, un garde ferme la porte derrière eux. Catelyn sent que quelque chose ne va pas... La pire trahison qui soit vient de se mettre en marche.\r\n\r\n \r\n\r\nLorsque le groupe joue le thème musical à la gloire de la Maison Lannister, "les Pluies de Castamere", la tension dramatique s'accélère et est amplifiée par l'arrivée d'Arya dans la ville. Frey entame un discours ambivalent et Lady Stark comprend le guet-appens dans lequel ils sont tombés lorsqu'elle soulève la manche de Roose Bolton et découvre qu'il porte une cotte de maille. Elle prévient Robb et là, tout s'enchaîne. Talisa est poignardée au ventre. Tétanisé, Robb est attaqué de toute part par des flèches. Il s'effondre alors que tous ses hommes se font assassiner. A son tour, Catlyn est touchée et Robb rampe pour se rapprocher de l'amour de sa vie, étendue morte. Il n'a plus aucune réaction. Tenant à la gorge la femme de Frey, Caltyn tente une dernière carte mais Frey s'en fiche totalement. Bolton s'avance vers Robb et le poignarde en lui murmurant : "Les Lannister vous présentent leurs hommages". Catlyn hurle de douleur et égorge la jeune femme avant d'être elle-même égorgée. Une scène qui dure, à elle seule, plus de 8 minutes... et dont on se remet très difficilement.
5	ATTENTION SPOIL !	Dans le poste précédent, on apprend qu'une grande partie de la ligné stark MEURT !
6	Troll	is Coming
7	Joffrey	Je désapprouve ce site.\r\nC'est moi qui aurait du être en tête
8	marco	les pommes vaincront\r\n\r\n<strong>il a fait gaffe le emmeran</strong>
\.


--
-- TOC entry 3181 (class 0 OID 0)
-- Dependencies: 182
-- Name: comment_comment__new_id_seq1; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('comment_comment__new_id_seq1', 15, true);


--
-- TOC entry 3131 (class 0 OID 1791455)
-- Dependencies: 204
-- Data for Name: comment_compteur; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY comment_compteur (compteur, id) FROM stdin;
8	1
\.


--
-- TOC entry 3182 (class 0 OID 0)
-- Dependencies: 203
-- Name: comment_compteur_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('comment_compteur_id_seq', 1, false);


--
-- TOC entry 3112 (class 0 OID 1727167)
-- Dependencies: 185
-- Data for Name: contact_article; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY contact_article (id, sujet, auteur, message, lu) FROM stdin;
1	lol	lol	lol	f
\.


--
-- TOC entry 3183 (class 0 OID 0)
-- Dependencies: 184
-- Name: contact_article_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('contact_article_id_seq', 2, true);


--
-- TOC entry 3129 (class 0 OID 1788837)
-- Dependencies: 202
-- Data for Name: vote_citation; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_citation (cit, id, auteur) FROM stdin;
Winter is coming.                                                                                                                                                                                       	1	Ned Stark                                                                                           
There is only one God, his name is Death. And there is only one thing we say to Death : “Not today”.                                                                                                    	2	Syrio Forel                                                                                         
Fuck the King                                                                                                                                                                                           	3	The Hound                                                                                           
THE MAN WHO PASSES THE SENTENCE SHOULD SWING THE SWORD.                                                                                                                                                 	4	Ned Stark                                                                                           
THE THINGS I DO FOR LOVE.                                                                                                                                                                               	5	Jaime Lannister                                                                                     
THE NEXT TIME YOU RAISE A HAND TO ME WILL BE THE LAST TIME YOU HAVE HANDS!                                                                                                                              	6	Daenarys                                                                                            
WHEN YOU PLAY THE GAME OF THRONES, YOU WIN OR YOU DIE.                                                                                                                                                  	7	Cersei Lannister                                                                                    
YOUR JOY WILL TURN TO ASHES IN YOUR MOUTH.                                                                                                                                                              	8	Tyrion Lannister                                                                                    
A DRAGON IS NOT A SLAVE.                                                                                                                                                                                	9	Daenarys                                                                                            
BURN THEM ALL                                                                                                                                                                                           	10	the Mad King                                                                                        
IF YOU EVER CALL ME SISTER AGAIN, I'LL HAVE YOU STRANGLED IN YOUR SLEEP.                                                                                                                                	11	Cersei Lannister                                                                                    
THE LANNISTERS SEND THEIR REGARDS.                                                                                                                                                                      	12	Roose Bolton                                                                                        
YOU KNOW NOTHING, JON SNOW.                                                                                                                                                                             	13	Ygritte                                                                                             
YOU'RE NO SON OF MINE.                                                                                                                                                                                  	14	Tywin Lannister                                                                                     
THIS IS NOT THE DAY I DIE.                                                                                                                                                                              	15	Oberyn Martell                                                                                      
The Lord of Light wants his enemies burnt. The Drowned God wants his enemies drowned. Why are all the gods such vicious cunts? Where is the god of tits and wine?                                       	16	Tyrion Lannister                                                                                    
I'm not questioning your honor, Lord Janos. I'm denying its existence.                                                                                                                                  	17	Tyrion Lannister                                                                                    
Look at me. Look at my face. It’s the last thing you’ll see before you die.                                                                                                                             	18	Cersei Lannister                                                                                    
A girl is not ready to become No One. But she is ready to become Someone Else.                                                                                                                          	20	Jaqen H'ghar                                                                                        
It's not easy being drunk all the time. Everyone would do it, if it were easy.                                                                                                                          	21	Tyrion Lannister                                                                                    
I shouldn't make jokes. My mother taught me not to throw stones at cripples. But my father taught me, aim for their head.                                                                               	22	Ramsay Bolton                                                                                       
Hush Hodor! No more Hodoring!                                                                                                                                                                           	23	Bran                                                                                                
Hodor                                                                                                                                                                                                   	24	Walder                                                                                              
Some day I'm going to put a sword through your eye and out the back of your skull.                                                                                                                      	25	Arya Stark                                                                                          
What happens to your eagle after I kill you? Does he drift away like a kite that's had its string cut?                                                                                                  	26	Jon Snow                                                                                            
Any man dies with a clean sword, I'll rape his fucking corpse!                                                                                                                                          	27	The Hound                                                                                           
The gods have no mercy, that's why they're gods.                                                                                                                                                        	28	Cersei                                                                                              
Has anyone ever told you you're as boring as you are ugly?                                                                                                                                              	29	Jaime Lannister                                                                                     
They'll bend the knee or I'll destroy them.                                                                                                                                                             	30	Stannis                                                                                             
Power is power.                                                                                                                                                                                         	31	Cersei                                                                                              
There's a king in ever corner now                                                                                                                                                                       	32	Catelyn                                                                                             
-Three victories don't make you a conquerer. -It's better than three defeats.                                                                                                                           	33	Jaime et Robb                                                                                       
Tell me, which do you favor, your fingers or your tongue?                                                                                                                                               	34	Joffrey                                                                                             
-Stay low. -Stay low? -If you're lucky, no one will notice you.                                                                                                                                         	35	Bron et Tyrion                                                                                      
I have never been nothing. I am the blood of the dragon.                                                                                                                                                	36	Daenerys                                                                                            
We go home with an army. With Khal Drogo's army. I would let his whole tribe fuck you - all forty thousand men - and their horses too if that's what it took.                                           	37	Viserys                                                                                             
A Crown for a King.                                                                                                                                                                                     	38	Khal Drogo                                                                                          
Tell Lord Tywin winter is coming for him. Twenty thousand northerners marching south to find out if he really does shit gold.                                                                           	39	Robb                                                                                                
-How would you like to die, Tyrion, son of Tywin? -In my own bed, at the age of 80, with a belly full of wine and a girls mouth around my cock.                                                         	40	Shaggar et Tyrion                                                                                   
I did warn you not to trust me.                                                                                                                                                                         	41	Baelish                                                                                             
-You don't fight with honor! -No, he did.                                                                                                                                                               	42	Lysa Arryn et Bronn                                                                                 
No! You cannot touch me. I am the dragon! I want my crown!                                                                                                                                              	43	Viserys                                                                                             
-I'm not a cripple. -Then I'm not a dwarf. My father will be rejoiced to hear it.                                                                                                                       	44	Bran et Tyrion                                                                                      
\.


--
-- TOC entry 3184 (class 0 OID 0)
-- Dependencies: 201
-- Name: vote_citation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('vote_citation_id_seq', 44, true);


--
-- TOC entry 3101 (class 0 OID 1726681)
-- Dependencies: 174
-- Data for Name: vote_departement; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_departement (id, "NumDep", "NomDep") FROM stdin;
1	1	Ain
2	2	Aisne
3	3	Allier
5	5	Hautes-Alpes
4	4	Alpes-de-Haute-Provence
6	6	Alpes-Maritimes
7	7	Ardèche
8	8	Ardennes
9	9	Ariège
10	10	Aube
11	11	Aude
12	12	Aveyron
13	13	Bouches-du-Rhône
14	14	Calvados
15	15	Cantal
16	16	Charente
17	17	Charente-Maritime
18	18	Cher
19	19	Corrèze
20	20	Corse
22	21	Côte-d'or
23	22	Côtes-d'armor
24	23	Creuse
25	24	Dordogne
26	25	Doubs
27	26	Drôme
28	27	Eure
29	28	Eure-et-Loir
30	29	Finistère
31	30	Gard
32	31	Haute-Garonne
33	32	Gers
34	33	Gironde
35	34	Hérault
36	35	Ile-et-Vilaine
37	36	Indre
38	37	Indre-et-Loire
39	38	Isère
40	39	Jura
41	40	Landes
42	41	Loir-et-Cher
43	42	Loire
44	43	Haute-Loire
45	44	Loire-Atlantique
46	45	Loiret
47	46	Lot
48	47	Lot-et-Garonne
49	48	Lozère
50	49	Maine-et-Loire
51	50	Manche
52	51	Marne
53	52	Haute-Marne
54	53	Mayenne
55	54	Meurthe-et-Moselle
56	55	Meuse
57	56	Morbihan
58	57	Moselle
59	58	Nièvre
60	59	Nord
61	60	Oise
62	61	Orne
63	62	Pas-de-Calais
64	63	Puy-de-Dôme
65	64	Pyrénées-Atlantiques
66	65	Hautes-Pyrénées
67	66	Pyrénées-Orientales
68	67	Bas-Rhin
69	68	Haut-Rhin
70	69	Rhône
71	70	Haute-Saône
72	71	Saône-et-Loire
73	72	Sarthe
74	73	Savoie
75	74	Haute-Savoie
76	75	Paris
77	76	Seine-Maritime
78	77	Seine-et-Marne
79	78	Yvelines
80	79	Deux-Sèvres
81	80	Somme
82	81	Tarn
83	82	Tarn-et-Garonne
84	83	Var
85	84	Vaucluse
86	85	Vendée
87	86	Vienne
88	87	Haute-Vienne
89	88	Vosges
90	89	Yonne
91	90	Territoire de Belfort
92	91	Essonne
93	92	Hauts-de-Seine
94	93	Seine-Saint-Denis
95	94	Val-de-Marne
96	95	Val-d'oise
97	976	Mayotte
98	971	Guadeloupe
99	973	Guyane
100	972	Martinique
101	974	Réunion
\.


--
-- TOC entry 3185 (class 0 OID 0)
-- Dependencies: 173
-- Name: vote_departement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('vote_departement_id_seq', 1, false);


--
-- TOC entry 3108 (class 0 OID 1726890)
-- Dependencies: 181
-- Data for Name: vote_scoredep; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_scoredep (id, "ScoreDep", "NumDep_id", "VoteDep_id") FROM stdin;
441	3	35	1
179	1	1	3
286	2	14	6
870	1	88	6
177	0	1	1
178	0	1	2
180	0	1	4
181	0	1	5
182	0	1	6
183	0	1	7
184	0	1	8
185	0	2	1
186	0	2	2
187	0	2	3
188	0	2	4
189	0	2	5
190	0	2	6
191	0	2	7
192	0	2	8
193	0	3	1
194	0	3	2
195	0	3	3
196	0	3	4
197	0	3	5
198	0	3	6
199	0	3	7
200	0	3	8
201	0	4	1
202	0	4	2
203	0	4	3
204	0	4	4
205	0	4	5
206	0	4	6
207	0	4	7
208	0	4	8
209	0	5	1
210	0	5	2
211	0	5	3
212	0	5	4
213	0	5	5
214	0	5	6
215	0	5	7
216	0	5	8
217	0	6	1
218	0	6	2
219	0	6	3
220	0	6	4
221	0	6	5
222	0	6	6
223	0	6	7
224	0	6	8
225	0	7	1
226	0	7	2
227	0	7	3
228	0	7	4
229	0	7	5
230	0	7	6
231	0	7	7
232	0	7	8
233	0	8	1
234	0	8	2
235	0	8	3
236	0	8	4
237	0	8	5
238	0	8	6
239	0	8	7
240	0	8	8
241	0	9	1
242	0	9	2
243	0	9	3
244	0	9	4
245	0	9	5
246	0	9	6
247	0	9	7
248	0	9	8
249	0	10	1
250	0	10	2
251	0	10	3
252	0	10	4
253	0	10	5
254	0	10	6
255	0	10	7
256	0	10	8
257	0	11	1
258	0	11	2
259	0	11	3
260	0	11	4
261	0	11	5
262	0	11	6
263	0	11	7
264	0	11	8
265	0	12	1
266	0	12	2
267	0	12	3
268	0	12	4
269	0	12	5
270	0	12	6
271	0	12	7
272	0	12	8
273	0	13	1
274	0	13	2
275	0	13	3
276	0	13	4
277	0	13	5
278	0	13	6
279	0	13	7
280	0	13	8
281	0	14	1
282	0	14	2
283	0	14	3
284	0	14	4
285	0	14	5
287	0	14	7
288	0	14	8
289	0	15	1
290	0	15	2
291	0	15	3
292	0	15	4
293	0	15	5
294	0	15	6
295	0	15	7
296	0	15	8
297	0	16	1
298	0	16	2
299	0	16	3
300	0	16	4
301	0	16	5
302	0	16	6
303	0	16	7
304	0	16	8
305	0	17	1
306	0	17	2
307	0	17	3
308	0	17	4
309	0	17	5
310	0	17	6
311	0	17	7
312	0	17	8
313	0	18	1
314	0	18	2
315	0	18	3
316	0	18	4
317	0	18	5
318	0	18	6
319	0	18	7
320	0	18	8
321	0	19	1
322	0	19	2
323	0	19	3
324	0	19	4
325	0	19	5
326	0	19	6
327	0	19	7
328	0	19	8
329	0	20	1
330	0	20	2
331	0	20	3
332	0	20	4
333	0	20	5
334	0	20	6
335	0	20	7
336	0	20	8
337	0	22	1
338	0	22	2
339	0	22	3
340	0	22	4
341	0	22	5
342	0	22	6
343	0	22	7
344	0	22	8
345	0	23	1
346	0	23	2
347	0	23	3
348	0	23	4
349	0	23	5
350	0	23	6
351	0	23	7
352	0	23	8
353	0	24	1
354	0	24	2
355	0	24	3
356	0	24	4
357	0	24	5
358	0	24	6
359	0	24	7
360	0	24	8
361	0	25	1
362	0	25	2
363	0	25	3
364	0	25	4
365	0	25	5
366	0	25	6
367	0	25	7
368	0	25	8
369	0	26	1
370	0	26	2
371	0	26	3
372	0	26	4
373	0	26	5
374	0	26	6
375	0	26	7
376	0	26	8
377	0	27	1
378	0	27	2
379	0	27	3
380	0	27	4
381	0	27	5
382	0	27	6
383	0	27	7
384	0	27	8
385	0	28	1
386	0	28	2
387	0	28	3
388	0	28	4
389	0	28	5
390	0	28	6
391	0	28	7
392	0	28	8
393	0	29	1
394	0	29	2
395	0	29	3
396	0	29	4
397	0	29	5
398	0	29	6
399	0	29	7
400	0	29	8
401	0	30	1
402	0	30	2
403	0	30	3
404	0	30	4
405	0	30	5
406	0	30	6
407	0	30	7
408	0	30	8
409	0	31	1
410	0	31	2
411	0	31	3
412	0	31	4
413	0	31	5
414	0	31	6
415	0	31	7
416	0	31	8
417	0	32	1
419	0	32	3
420	0	32	4
421	0	32	5
422	0	32	6
423	0	32	7
424	0	32	8
425	0	33	1
426	0	33	2
427	0	33	3
428	0	33	4
429	0	33	5
430	0	33	6
431	0	33	7
432	0	33	8
433	0	34	1
434	0	34	2
435	0	34	3
436	0	34	4
437	0	34	5
438	0	34	6
439	0	34	7
440	0	34	8
443	0	35	3
444	0	35	4
445	0	35	5
447	0	35	7
448	0	35	8
449	0	36	1
450	0	36	2
451	0	36	3
452	0	36	4
453	0	36	5
454	0	36	6
455	0	36	7
456	0	36	8
457	0	37	1
458	0	37	2
459	0	37	3
460	0	37	4
461	0	37	5
462	0	37	6
463	0	37	7
464	0	37	8
465	0	38	1
466	0	38	2
467	0	38	3
468	0	38	4
469	0	38	5
470	0	38	6
471	0	38	7
472	0	38	8
473	0	39	1
474	0	39	2
475	0	39	3
476	0	39	4
477	0	39	5
478	0	39	6
479	0	39	7
480	0	39	8
481	0	40	1
482	0	40	2
483	0	40	3
484	0	40	4
485	0	40	5
486	0	40	6
487	0	40	7
488	0	40	8
489	0	41	1
490	0	41	2
491	0	41	3
492	0	41	4
493	0	41	5
494	0	41	6
495	0	41	7
496	0	41	8
497	0	42	1
498	0	42	2
499	0	42	3
500	0	42	4
501	0	42	5
502	0	42	6
503	0	42	7
504	0	42	8
505	0	43	1
506	0	43	2
507	0	43	3
508	0	43	4
509	0	43	5
510	0	43	6
511	0	43	7
512	0	43	8
513	0	44	1
514	0	44	2
515	0	44	3
516	0	44	4
517	0	44	5
518	0	44	6
519	0	44	7
520	0	44	8
521	0	45	1
522	0	45	2
523	0	45	3
524	0	45	4
525	0	45	5
442	1	35	2
418	1	32	2
446	2	35	6
526	0	45	6
527	0	45	7
528	0	45	8
529	0	46	1
530	0	46	2
531	0	46	3
532	0	46	4
533	0	46	5
534	0	46	6
535	0	46	7
536	0	46	8
537	0	47	1
538	0	47	2
539	0	47	3
540	0	47	4
541	0	47	5
542	0	47	6
543	0	47	7
544	0	47	8
545	0	48	1
546	0	48	2
547	0	48	3
548	0	48	4
549	0	48	5
550	0	48	6
551	0	48	7
552	0	48	8
553	0	49	1
554	0	49	2
555	0	49	3
556	0	49	4
557	0	49	5
558	0	49	6
559	0	49	7
560	0	49	8
561	0	50	1
562	0	50	2
563	0	50	3
564	0	50	4
565	0	50	5
566	0	50	6
567	0	50	7
568	0	50	8
569	0	51	1
570	0	51	2
571	0	51	3
572	0	51	4
573	0	51	5
574	0	51	6
575	0	51	7
576	0	51	8
577	0	52	1
578	0	52	2
579	0	52	3
580	0	52	4
581	0	52	5
582	0	52	6
583	0	52	7
584	0	52	8
585	0	53	1
586	0	53	2
587	0	53	3
588	0	53	4
589	0	53	5
590	0	53	6
591	0	53	7
592	0	53	8
593	0	54	1
594	0	54	2
595	0	54	3
596	0	54	4
597	0	54	5
598	0	54	6
599	0	54	7
600	0	54	8
601	0	55	1
602	0	55	2
603	0	55	3
604	0	55	4
605	0	55	5
606	0	55	6
607	0	55	7
608	0	55	8
609	0	56	1
610	0	56	2
611	0	56	3
612	0	56	4
613	0	56	5
614	0	56	6
615	0	56	7
616	0	56	8
617	0	57	1
618	0	57	2
619	0	57	3
620	0	57	4
621	0	57	5
622	0	57	6
623	0	57	7
624	0	57	8
625	0	58	1
626	0	58	2
627	0	58	3
628	0	58	4
629	0	58	5
630	0	58	6
631	0	58	7
632	0	58	8
633	0	59	1
634	0	59	2
635	0	59	3
636	0	59	4
637	0	59	5
638	0	59	6
639	0	59	7
640	0	59	8
641	0	60	1
642	0	60	2
643	0	60	3
644	0	60	4
645	0	60	5
646	0	60	6
647	0	60	7
648	0	60	8
649	0	61	1
650	0	61	2
651	0	61	3
652	0	61	4
653	0	61	5
654	0	61	6
655	0	61	7
656	0	61	8
657	0	62	1
658	0	62	2
659	0	62	3
660	0	62	4
661	0	62	5
662	0	62	6
663	0	62	7
664	0	62	8
665	0	63	1
666	0	63	2
667	0	63	3
668	0	63	4
669	0	63	5
670	0	63	6
671	0	63	7
672	0	63	8
673	0	64	1
674	0	64	2
675	0	64	3
676	0	64	4
677	0	64	5
678	0	64	6
679	0	64	7
680	0	64	8
681	0	65	1
682	0	65	2
683	0	65	3
684	0	65	4
685	0	65	5
686	0	65	6
687	0	65	7
688	0	65	8
689	0	66	1
690	0	66	2
691	0	66	3
692	0	66	4
693	0	66	5
694	0	66	6
695	0	66	7
696	0	66	8
697	0	67	1
698	0	67	2
699	0	67	3
700	0	67	4
701	0	67	5
702	0	67	6
703	0	67	7
704	0	67	8
705	0	68	1
706	0	68	2
707	0	68	3
708	0	68	4
709	0	68	5
710	0	68	6
711	0	68	7
712	0	68	8
713	0	69	1
714	0	69	2
715	0	69	3
716	0	69	4
717	0	69	5
718	0	69	6
719	0	69	7
720	0	69	8
721	0	70	1
722	0	70	2
723	0	70	3
724	0	70	4
725	0	70	5
726	0	70	6
727	0	70	7
728	0	70	8
729	0	71	1
730	0	71	2
731	0	71	3
732	0	71	4
733	0	71	5
734	0	71	6
735	0	71	7
736	0	71	8
737	0	72	1
738	0	72	2
739	0	72	3
740	0	72	4
741	0	72	5
742	0	72	6
743	0	72	7
744	0	72	8
745	0	73	1
746	0	73	2
747	0	73	3
748	0	73	4
749	0	73	5
750	0	73	6
751	0	73	7
752	0	73	8
753	0	74	1
754	0	74	2
755	0	74	3
756	0	74	4
757	0	74	5
758	0	74	6
759	0	74	7
760	0	74	8
761	0	75	1
762	0	75	2
763	0	75	3
764	0	75	4
765	0	75	5
766	0	75	6
767	0	75	7
768	0	75	8
769	0	76	1
770	0	76	2
771	0	76	3
772	0	76	4
773	0	76	5
774	0	76	6
775	0	76	7
776	0	76	8
777	0	77	1
778	0	77	2
779	0	77	3
780	0	77	4
781	0	77	5
782	0	77	6
783	0	77	7
784	0	77	8
785	0	78	1
786	0	78	2
787	0	78	3
788	0	78	4
789	0	78	5
790	0	78	6
791	0	78	7
792	0	78	8
793	0	79	1
794	0	79	2
795	0	79	3
796	0	79	4
797	0	79	5
798	0	79	6
799	0	79	7
800	0	79	8
801	0	80	1
802	0	80	2
803	0	80	3
804	0	80	4
805	0	80	5
806	0	80	6
807	0	80	7
808	0	80	8
809	0	81	1
810	0	81	2
811	0	81	3
812	0	81	4
813	0	81	5
814	0	81	6
815	0	81	7
816	0	81	8
817	0	82	1
818	0	82	2
819	0	82	3
820	0	82	4
821	0	82	5
822	0	82	6
823	0	82	7
824	0	82	8
825	0	83	1
826	0	83	2
827	0	83	3
828	0	83	4
829	0	83	5
830	0	83	6
831	0	83	7
832	0	83	8
833	0	84	1
834	0	84	2
835	0	84	3
836	0	84	4
837	0	84	5
838	0	84	6
839	0	84	7
840	0	84	8
841	0	85	1
842	0	85	2
843	0	85	3
844	0	85	4
845	0	85	5
846	0	85	6
847	0	85	7
848	0	85	8
849	0	86	1
850	0	86	2
851	0	86	3
852	0	86	4
853	0	86	5
854	0	86	6
855	0	86	7
856	0	86	8
857	0	87	1
858	0	87	2
859	0	87	3
860	0	87	4
861	0	87	5
862	0	87	6
863	0	87	7
864	0	87	8
865	0	88	1
866	0	88	2
867	0	88	3
868	0	88	4
869	0	88	5
871	0	88	7
872	0	88	8
873	0	89	1
874	0	89	2
875	0	89	3
876	0	89	4
877	0	89	5
878	0	89	6
879	0	89	7
880	0	89	8
881	0	90	1
882	0	90	2
883	0	90	3
884	0	90	4
885	0	90	5
886	0	90	6
887	0	90	7
888	0	90	8
889	0	91	1
890	0	91	2
891	0	91	3
892	0	91	4
893	0	91	5
894	0	91	6
895	0	91	7
896	0	91	8
897	0	92	1
898	0	92	2
899	0	92	3
900	0	92	4
901	0	92	5
902	0	92	6
903	0	92	7
904	0	92	8
905	0	93	1
906	0	93	2
907	0	93	3
908	0	93	4
909	0	93	5
910	0	93	6
911	0	93	7
912	0	93	8
913	0	94	1
914	0	94	2
915	0	94	3
916	0	94	4
917	0	94	5
918	0	94	6
919	0	94	7
920	0	94	8
921	0	95	1
922	0	95	2
923	0	95	3
924	0	95	4
925	0	95	5
926	0	95	6
927	0	95	7
928	0	95	8
929	0	96	1
930	0	96	2
931	0	96	3
932	0	96	4
933	0	96	5
934	0	96	6
935	0	96	7
936	0	96	8
937	0	97	1
938	0	97	2
939	0	97	3
940	0	97	4
941	0	97	5
942	0	97	6
943	0	97	7
944	0	97	8
945	0	98	1
946	0	98	2
947	0	98	3
948	0	98	4
949	0	98	5
950	0	98	6
951	0	98	7
952	0	98	8
953	0	99	1
954	0	99	2
955	0	99	3
956	0	99	4
957	0	99	5
958	0	99	6
959	0	99	7
960	0	99	8
961	0	100	1
962	0	100	2
963	0	100	3
964	0	100	4
965	0	100	5
966	0	100	6
967	0	100	7
968	0	100	8
969	0	101	1
970	0	101	2
972	0	101	4
973	0	101	5
974	0	101	6
975	0	101	7
976	0	101	8
971	1	101	3
\.


--
-- TOC entry 3186 (class 0 OID 0)
-- Dependencies: 180
-- Name: vote_scoredep__new_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('vote_scoredep__new_id_seq', 976, true);


--
-- TOC entry 3106 (class 0 OID 1726871)
-- Dependencies: 179
-- Data for Name: vote_votant; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_votant (id, ipvotant) FROM stdin;
85	92.143.13.69
86	109.25.77.166
87	46.193.65.3
88	78.115.202.240
89	46.193.64.237
90	86.220.28.198
91	109.223.183.15
92	212.195.16.238
93	128.78.49.197
94	80.12.35.253
95	88.166.3.156
96	128.79.127.237
\.


--
-- TOC entry 3187 (class 0 OID 0)
-- Dependencies: 178
-- Name: vote_votant__new_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('vote_votant__new_id_seq', 96, true);


--
-- TOC entry 3102 (class 0 OID 1726700)
-- Dependencies: 175
-- Data for Name: vote_vote; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_vote ("NumVote", "Score", "NomVote", "ImgVote") FROM stdin;
3	2	Bran Stark, s'il contrôle Hodor pourquoi pas?	static/images/bran.jpg
6	5	Jon Snow, parce qu'il ne le sait pas encore	static/images/jon_swon.jpeg
2	2	Les Autres, les zombies des glaces	static/images/autres.jpg
1	3	Arya Stark, une fois qu'elle aura finit sa liste	static/images/arya_sZ3hmh6.JPG
4	0	Daenerys of the House Targaryen, the First of Her Name, Queen of Meereen, Queen of the Andals, ...	static/images/daenarys.png
5	0	Les dragons (vouivres) de Daenarys	static/images/dragons.jpg
7	0	Melisandre, glory to R'hllor	static/images/melisandre.jpg
8	0	Tommen... lol	static/images/tommen.jpg
\.


--
-- TOC entry 3104 (class 0 OID 1726739)
-- Dependencies: 177
-- Data for Name: vote_voteform; Type: TABLE DATA; Schema: public; Owner: bpprsodytbgwip
--

COPY vote_voteform (id, "formDep", "formVote") FROM stdin;
\.


--
-- TOC entry 3188 (class 0 OID 0)
-- Dependencies: 176
-- Name: vote_voteform_id_seq; Type: SEQUENCE SET; Schema: public; Owner: bpprsodytbgwip
--

SELECT pg_catalog.setval('vote_voteform_id_seq', 1, false);


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 2965 (class 2606 OID 1754044)
-- Name: pga_exception_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_pkey PRIMARY KEY (jexid);


--
-- TOC entry 2955 (class 2606 OID 1753970)
-- Name: pga_job_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_pkey PRIMARY KEY (jobid);


--
-- TOC entry 2950 (class 2606 OID 1753942)
-- Name: pga_jobagent_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_jobagent
    ADD CONSTRAINT pga_jobagent_pkey PRIMARY KEY (jagpid);


--
-- TOC entry 2953 (class 2606 OID 1753953)
-- Name: pga_jobclass_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_jobclass
    ADD CONSTRAINT pga_jobclass_pkey PRIMARY KEY (jclid);


--
-- TOC entry 2968 (class 2606 OID 1754062)
-- Name: pga_joblog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_pkey PRIMARY KEY (jlgid);


--
-- TOC entry 2958 (class 2606 OID 1754000)
-- Name: pga_jobstep_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_pkey PRIMARY KEY (jstid);


--
-- TOC entry 2971 (class 2606 OID 1754082)
-- Name: pga_jobsteplog_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_pkey PRIMARY KEY (jslid);


--
-- TOC entry 2961 (class 2606 OID 1754030)
-- Name: pga_schedule_pkey; Type: CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_pkey PRIMARY KEY (jscid);


SET search_path = public, pg_catalog;

--
-- TOC entry 2946 (class 2606 OID 1727066)
-- Name: comment_comment__new_pkey1; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY comment_comment
    ADD CONSTRAINT comment_comment__new_pkey1 PRIMARY KEY (id);


--
-- TOC entry 2948 (class 2606 OID 1727175)
-- Name: contact_article_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY contact_article
    ADD CONSTRAINT contact_article_pkey PRIMARY KEY (id);


--
-- TOC entry 2975 (class 2606 OID 1791461)
-- Name: pk_compteur; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY comment_compteur
    ADD CONSTRAINT pk_compteur PRIMARY KEY (id);


--
-- TOC entry 2973 (class 2606 OID 1788842)
-- Name: vote_citation_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_citation
    ADD CONSTRAINT vote_citation_pkey PRIMARY KEY (id);


--
-- TOC entry 2934 (class 2606 OID 1726686)
-- Name: vote_departement_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_departement
    ADD CONSTRAINT vote_departement_pkey PRIMARY KEY (id);


--
-- TOC entry 2943 (class 2606 OID 1726895)
-- Name: vote_scoredep__new_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_scoredep
    ADD CONSTRAINT vote_scoredep__new_pkey PRIMARY KEY (id);


--
-- TOC entry 2940 (class 2606 OID 1726876)
-- Name: vote_votant__new_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_votant
    ADD CONSTRAINT vote_votant__new_pkey PRIMARY KEY (id);


--
-- TOC entry 2936 (class 2606 OID 1726704)
-- Name: vote_vote_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_vote
    ADD CONSTRAINT vote_vote_pkey PRIMARY KEY ("NumVote");


--
-- TOC entry 2938 (class 2606 OID 1726744)
-- Name: vote_voteform_pkey; Type: CONSTRAINT; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

ALTER TABLE ONLY vote_voteform
    ADD CONSTRAINT vote_voteform_pkey PRIMARY KEY (id);


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 2962 (class 1259 OID 1754051)
-- Name: pga_exception_datetime; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE UNIQUE INDEX pga_exception_datetime ON pga_exception USING btree (jexdate, jextime);


--
-- TOC entry 2963 (class 1259 OID 1754050)
-- Name: pga_exception_jexscid; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX pga_exception_jexscid ON pga_exception USING btree (jexscid);


--
-- TOC entry 2951 (class 1259 OID 1753954)
-- Name: pga_jobclass_name; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE UNIQUE INDEX pga_jobclass_name ON pga_jobclass USING btree (jclname);


--
-- TOC entry 2966 (class 1259 OID 1754068)
-- Name: pga_joblog_jobid; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX pga_joblog_jobid ON pga_joblog USING btree (jlgjobid);


--
-- TOC entry 2959 (class 1259 OID 1754036)
-- Name: pga_jobschedule_jobid; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX pga_jobschedule_jobid ON pga_schedule USING btree (jscjobid);


--
-- TOC entry 2956 (class 1259 OID 1754006)
-- Name: pga_jobstep_jobid; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX pga_jobstep_jobid ON pga_jobstep USING btree (jstjobid);


--
-- TOC entry 2969 (class 1259 OID 1754093)
-- Name: pga_jobsteplog_jslid; Type: INDEX; Schema: pgagent; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX pga_jobsteplog_jslid ON pga_jobsteplog USING btree (jsljlgid);


SET search_path = public, pg_catalog;

--
-- TOC entry 2941 (class 1259 OID 1726907)
-- Name: vote_scoredep_4f0624d5; Type: INDEX; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX vote_scoredep_4f0624d5 ON vote_scoredep USING btree ("VoteDep_id");


--
-- TOC entry 2944 (class 1259 OID 1726906)
-- Name: vote_scoredep_df5c358a; Type: INDEX; Schema: public; Owner: bpprsodytbgwip; Tablespace: 
--

CREATE INDEX vote_scoredep_df5c358a ON vote_scoredep USING btree ("NumDep_id");


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 2990 (class 2620 OID 1754103)
-- Name: pga_exception_trigger; Type: TRIGGER; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE TRIGGER pga_exception_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_exception FOR EACH ROW EXECUTE PROCEDURE pga_exception_trigger();


--
-- TOC entry 3189 (class 0 OID 0)
-- Dependencies: 2990
-- Name: TRIGGER pga_exception_trigger ON pga_exception; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TRIGGER pga_exception_trigger ON pga_exception IS 'Update the job''s next run time whenever an exception changes';


--
-- TOC entry 2988 (class 2620 OID 1754099)
-- Name: pga_job_trigger; Type: TRIGGER; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE TRIGGER pga_job_trigger BEFORE UPDATE ON pga_job FOR EACH ROW EXECUTE PROCEDURE pga_job_trigger();


--
-- TOC entry 3190 (class 0 OID 0)
-- Dependencies: 2988
-- Name: TRIGGER pga_job_trigger ON pga_job; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TRIGGER pga_job_trigger ON pga_job IS 'Update the job''s next run time.';


--
-- TOC entry 2989 (class 2620 OID 1754101)
-- Name: pga_schedule_trigger; Type: TRIGGER; Schema: pgagent; Owner: bpprsodytbgwip
--

CREATE TRIGGER pga_schedule_trigger AFTER INSERT OR DELETE OR UPDATE ON pga_schedule FOR EACH ROW EXECUTE PROCEDURE pga_schedule_trigger();


--
-- TOC entry 3191 (class 0 OID 0)
-- Dependencies: 2989
-- Name: TRIGGER pga_schedule_trigger ON pga_schedule; Type: COMMENT; Schema: pgagent; Owner: bpprsodytbgwip
--

COMMENT ON TRIGGER pga_schedule_trigger ON pga_schedule IS 'Update the job''s next run time whenever a schedule changes';


SET search_path = public, pg_catalog;

--
-- TOC entry 2987 (class 2620 OID 1756934)
-- Name: clear_contact; Type: TRIGGER; Schema: public; Owner: bpprsodytbgwip
--

CREATE TRIGGER clear_contact AFTER UPDATE ON contact_article FOR EACH ROW EXECUTE PROCEDURE clear_contact();


--
-- TOC entry 2986 (class 2620 OID 1791556)
-- Name: compteur_commentaire; Type: TRIGGER; Schema: public; Owner: bpprsodytbgwip
--

CREATE TRIGGER compteur_commentaire AFTER INSERT OR DELETE ON comment_comment FOR EACH ROW EXECUTE PROCEDURE compteur_commentaire();


SET search_path = pgagent, pg_catalog;

--
-- TOC entry 2982 (class 2606 OID 1754045)
-- Name: pga_exception_jexscid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_exception
    ADD CONSTRAINT pga_exception_jexscid_fkey FOREIGN KEY (jexscid) REFERENCES pga_schedule(jscid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 2979 (class 2606 OID 1753976)
-- Name: pga_job_jobagentid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobagentid_fkey FOREIGN KEY (jobagentid) REFERENCES pga_jobagent(jagpid) ON UPDATE RESTRICT ON DELETE SET NULL;


--
-- TOC entry 2978 (class 2606 OID 1753971)
-- Name: pga_job_jobjclid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_job
    ADD CONSTRAINT pga_job_jobjclid_fkey FOREIGN KEY (jobjclid) REFERENCES pga_jobclass(jclid) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 2983 (class 2606 OID 1754063)
-- Name: pga_joblog_jlgjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_joblog
    ADD CONSTRAINT pga_joblog_jlgjobid_fkey FOREIGN KEY (jlgjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 2980 (class 2606 OID 1754001)
-- Name: pga_jobstep_jstjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobstep
    ADD CONSTRAINT pga_jobstep_jstjobid_fkey FOREIGN KEY (jstjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 2984 (class 2606 OID 1754083)
-- Name: pga_jobsteplog_jsljlgid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljlgid_fkey FOREIGN KEY (jsljlgid) REFERENCES pga_joblog(jlgid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 2985 (class 2606 OID 1754088)
-- Name: pga_jobsteplog_jsljstid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_jobsteplog
    ADD CONSTRAINT pga_jobsteplog_jsljstid_fkey FOREIGN KEY (jsljstid) REFERENCES pga_jobstep(jstid) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- TOC entry 2981 (class 2606 OID 1754031)
-- Name: pga_schedule_jscjobid_fkey; Type: FK CONSTRAINT; Schema: pgagent; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY pga_schedule
    ADD CONSTRAINT pga_schedule_jscjobid_fkey FOREIGN KEY (jscjobid) REFERENCES pga_job(jobid) ON UPDATE RESTRICT ON DELETE CASCADE;


SET search_path = public, pg_catalog;

--
-- TOC entry 2976 (class 2606 OID 1726896)
-- Name: vote_scoredep__new_NumDep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_scoredep
    ADD CONSTRAINT "vote_scoredep__new_NumDep_id_fkey" FOREIGN KEY ("NumDep_id") REFERENCES vote_departement(id);


--
-- TOC entry 2977 (class 2606 OID 1726901)
-- Name: vote_scoredep__new_VoteDep_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: bpprsodytbgwip
--

ALTER TABLE ONLY vote_scoredep
    ADD CONSTRAINT "vote_scoredep__new_VoteDep_id_fkey" FOREIGN KEY ("VoteDep_id") REFERENCES vote_vote("NumVote");


--
-- TOC entry 3139 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: bpprsodytbgwip
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM bpprsodytbgwip;
GRANT ALL ON SCHEMA public TO bpprsodytbgwip;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2015-05-31 15:40:52

--
-- PostgreSQL database dump complete
--

