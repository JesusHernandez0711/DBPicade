/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarEstatusCapacitacion
   ============================================================================================
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (THE "WHY")
   --------------------------------------------
   Gestionar el alta de nuevos estados para el ciclo de vida de las capacitaciones (ej: 'PROGRAMADO', 
   'EN CURSO', 'CANCELADO'). Este SP es la base de la máquina de estados que rige la lógica de 
   negocio y los bloqueos operativos (Killswitches) en todo el sistema.

   2. ESTRATEGIA DE BLINDAJE "DIAMOND" (CONTRATO DE INTEGRIDAD)
   -----------------------------------------------------------
   A) IDENTIDAD UNÍVOCA DE DOBLE NIVEL:
      - Unicidad Técnica: El `Código` (Slug) debe ser único (ej: 'PROG').
      - Unicidad Semántica: El `Nombre` legible debe ser único (ej: 'PROGRAMADO').
      - Resolución: Se verifica primero el código y luego el nombre para evitar colisiones 
        o ambigüedades operativas.

   B) PATRÓN DE IDEMPOTENCIA (SMART REGISTER):
      - Si el estatus ya existe y está ACTIVO: No genera duplicados (Reporta 'REUSADA').
      - Si el estatus existe pero está INACTIVO: Ejecuta una **Reactivación Lógica** (Reporta 'REACTIVADA').
      - Esto evita el crecimiento innecesario de la tabla y permite recuperar historial.

   C) MANEJO DE CONCURRENCIA AVANZADA (RACE CONDITIONS):
      - Implementa el patrón "Re-Resolve" mediante un Handler para el error 1062.
      - Si dos administradores insertan el mismo estatus al mismo milisegundo, el sistema atrapa 
        el error, revierte la transacción fallida y busca el registro que "ganó la carrera" 
        para devolverlo con éxito transparente al usuario.

   3. DICCIONARIO DE PARÁMETROS (INTERFACE)
   ----------------------------------------
   - _Codigo:      (VARCHAR 50) Clave corta obligatoria para lógica de sistema.
   - _Nombre:      (VARCHAR 255) Etiqueta oficial obligatoria para visualización en UI.
   - _Descripcion: (VARCHAR 255) Texto contextual sobre el uso del estatus.
   - _Es_Final:    (TINYINT 1) Interruptor: 1 indica que este estado concluye la capacitación 
                    y libera los bloqueos de los temas involucrados.

   4. RESULTADO (OUTPUT)
   ---------------------
   Devuelve un resultset con:
   - Mensaje: Feedback legible para el usuario.
   - Id_Estatus: Llave primaria del registro (nuevo o recuperado).
   - Accion: Enumerador técnico ['CREADA', 'REACTIVADA', 'REUSADA'].
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarEstatusCapacitacion`(
    IN _Codigo      VARCHAR(50),
    IN _Nombre      VARCHAR(255),
    IN _Descripcion VARCHAR(255),
    IN _Es_Final     TINYINT(1)
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       ---------------------------------------------------------------------------------------- */
    /* Variables de Persistencia (Snapshot del registro en BD) */
    DECLARE v_Id_Estatus INT DEFAULT NULL;
    DECLARE v_Activo     TINYINT(1) DEFAULT NULL;
    
    /* Variables para Validación Cruzada de Identidad */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Semáforo para Concurrencia (Error 1062) */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* ----------------------------------------------------------------------------------------
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       ---------------------------------------------------------------------------------------- */
    
    /* 1.1 HANDLER DE DUPLICIDAD: Captura colisiones de Unique Key en el INSERT. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO: Aborta y revierte ante fallos de infraestructura. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ----------------------------------------------------------------------------------------
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN (FAIL FAST)
       ---------------------------------------------------------------------------------------- */
    
    /* 2.1 Limpieza de strings y normalización de nulos */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    SET _Es_Final    = IFNULL(_Es_Final, 0);

    /* 2.2 Validación de obligatoriedad técnica */
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del estatus es mandatorio.';
    END IF;

    /* 2.3 Validación de obligatoriedad semántica */
    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del estatus es mandatorio.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       BLOQUE 3: FASE TRANSACCIONAL (CORE LOGIC)
       ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    /* 3.1 RESOLUCIÓN POR CÓDIGO (IDENTIDAD PRIMARIA)
       Buscamos con bloqueo de escritura (FOR UPDATE) para serializar peticiones concurrentes. */
    SET v_Id_Estatus = NULL;

    SELECT `Id_CatEstCap`, `Nombre`, `Activo` 
    INTO v_Id_Estatus, v_Nombre_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Codigo` = _Codigo LIMIT 1 
    FOR UPDATE;

    IF v_Id_Estatus IS NOT NULL THEN
        /* Conflicto: El código existe pero con diferente nombre. */
        IF v_Nombre_Existente <> _Nombre THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero está asignado a otro nombre.';
        END IF;

        /* Caso: Reactivación (Self-Healing) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion`
            SET `Activo` = 1,
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`),
                `Es_Final` = _Es_Final,
                `updated_at` = NOW()
            WHERE `Id_CatEstCap` = v_Id_Estatus;
            
            COMMIT;
            SELECT 'ÉXITO: Estatus reactivado y actualizado.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
            LEAVE SP;
        ELSE
            /* Caso: Idempotencia (Sin cambios) */
            COMMIT;
            SELECT 'AVISO: El Estatus ya se encuentra activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
            LEAVE SP;
        END IF;
    END IF;

    /* 3.2 RESOLUCIÓN POR NOMBRE (IDENTIDAD SECUNDARIA)
       Si el código es nuevo, verificamos que el nombre no esté ocupado por otra clave. */
    SET v_Id_Estatus = NULL;
    SET v_Codigo_Existente = NULL;

    SELECT `Id_CatEstCap`, `Codigo`, `Activo`
    INTO v_Id_Estatus, v_Codigo_Existente, v_Activo
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Nombre` = _Nombre LIMIT 1
    FOR UPDATE;

    IF v_Id_Estatus IS NOT NULL THEN
        /* Conflicto de ambigüedad: El nombre existe con otro código. */
        IF v_Codigo_Existente <> _Codigo THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ya existe asociado a otro CÓDIGO diferente.';
        END IF;
    END IF;

    /* 3.3 PERSISTENCIA FÍSICA (INSERCIÓN)
       Ejecución del comando de escritura. La bandera v_Dup se activará si ocurre 1062. */
    SET v_Dup = 0;

    INSERT INTO `Cat_Estatus_Capacitacion` (
        `Codigo`, `Nombre`, `Descripcion`, `Es_Final`, `Activo`
    ) VALUES (
        _Codigo, _Nombre, _Descripcion, _Es_Final, 1
    );

    IF v_Dup = 0 THEN
        COMMIT;
        SELECT 'ÉXITO: Estatus registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Estatus, 'CREADA' AS Accion;
        LEAVE SP;
    END IF;

    /* ----------------------------------------------------------------------------------------
       BLOQUE 4: RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE)
       ---------------------------------------------------------------------------------------- */
    ROLLBACK; -- Limpiamos el intento fallido
    
    START TRANSACTION; -- Iniciamos búsqueda del registro ganador
    
    SET v_Id_Estatus = NULL;

    SELECT `Id_CatEstCap`, `Activo`, `Nombre`
    INTO v_Id_Estatus, v_Activo, v_Nombre_Existente
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Codigo` = _Codigo LIMIT 1
    FOR UPDATE;

    IF v_Id_Estatus IS NOT NULL THEN
        /* Reactivación tras concurrencia */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Capacitacion` SET `Activo` = 1, `updated_at` = NOW() WHERE `Id_CatEstCap` = v_Id_Estatus;
            COMMIT;
            SELECT 'ÉXITO: Estatus reactivado (tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REACTIVADA' AS Accion;
        ELSE
            /* Reuso tras concurrencia */
            COMMIT;
            SELECT 'AVISO: Estatus ya existente (reusado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus, 'REUSADA' AS Accion;
        END IF;
        LEAVE SP;
    END IF;

    /* Fallo irrecuperable (Corrupción o error fantasma) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable al registrar Estatus.';

END$$

DELIMITER ;