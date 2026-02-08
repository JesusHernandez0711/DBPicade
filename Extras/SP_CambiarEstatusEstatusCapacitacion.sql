/* ====================================================================================================
	PROCEDIMEINTOS: SP_CambiarEstatusEstatusCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento administra el mecanismo de "Baja Lógica" (Soft Delete) para el catálogo maestro
   de Estatus de Capacitación.
   
   Permite al Administrador:
     A) DESACTIVAR (Ocultar): Retirar un estatus de los selectores para que no se use en nuevas
        capacitaciones (ej: un estatus obsoleto como "PENDIENTE DE FIRMA").
     B) REACTIVAR (Mostrar): Recuperar un estatus histórico para volver a utilizarlo.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO DESCENDENTE (DEPENDENCY CHECK):
      - Problema: Si desactivamos el estatus "EN CURSO" mientras hay 50 cursos impartiéndose en ese
        momento, rompemos la integridad visual del sistema. Los cursos aparecerían con un estatus
        "nulo" o inválido en los reportes.
      - Solución: Antes de desactivar (`_Nuevo_Estatus = 0`), el sistema escanea la tabla operativa
        `DatosCapacitaciones`.
      - Condición de Bloqueo: Si existe AL MENOS UNA capacitación activa (`Activo = 1`) que tenga
        asignado este estatus, la operación se ABORTA con un error 409 (Conflicto).

   [RN-02] PROTECCIÓN DE HISTORIAL:
      - Nota Técnica: La validación solo busca capacitaciones ACTIVAS. Si el estatus fue usado en
        capacitaciones de hace 5 años que ya están borradas o archivadas, NO bloqueamos la baja.
        Esto permite limpiar el catálogo sin quedar "secuestrados" por el pasado.

   ----------------------------------------------------------------------------------------------------
   III. ARQUITECTURA TÉCNICA (CONCURRENCY & PERFORMANCE)
   ----------------------------------------------------------------------------------------------------
   1. BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` al inicio.
      - Esto "congela" la fila del estatus. Garantiza que nadie más edite el nombre o la lógica
        del estatus mientras nosotros estamos decidiendo si lo apagamos o no.

   2. IDEMPOTENCIA (OPTIMIZACIÓN DE I/O):
      - Antes de escribir en disco, verificamos: ¿El estatus ya está como lo pide el usuario?
      - Si `Activo_Actual == Nuevo_Estatus`, retornamos éxito inmediato sin realizar el UPDATE.
      - Beneficio: Ahorra ciclos de escritura en disco y evita "ensuciar" el log de transacciones.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (OUTPUT)
   ----------------------------------------------------------------------------------------------------
   Retorna una fila con:
      - Mensaje: Feedback claro para la UI.
      - Accion: 'ESTATUS_CAMBIADO', 'SIN_CAMBIOS'.
      - Id_Estatus: El recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusEstatusCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Estatus     INT,     -- [OBLIGATORIO] Identificador del Estatus a modificar.
    IN _Nuevo_Estatus  TINYINT  -- [OBLIGATORIO] 1 = Activar (Visible), 0 = Desactivar (Oculto).
)
THIS_PROC: BEGIN

    /* ============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO
       Contenedores para almacenar la "foto" del registro y auxiliares de validación.
       ============================================================================================ */
    
    /* Variable para validar existencia y bloquear la fila */
    DECLARE v_Existe INT DEFAULT NULL;
    
    /* Variables para el Snapshot (Estado Actual) */
    DECLARE v_Activo_Actual  TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre_Estatus VARCHAR(255) DEFAULT NULL;
    
    /* Semáforo para contar dependencias activas (Hijos en DatosCapacitaciones) */
    DECLARE v_Dependencias   INT DEFAULT NULL;

    /* ============================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Manejo robusto de errores técnicos.
       ============================================================================================ */
    
    /* Handler Genérico: Ante cualquier error SQL (Deadlock, Conexión perdida, etc.),
       revertimos la transacción para mantener la consistencia de la BD. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al backend.
    END;

    /* ============================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Rechazar peticiones basura antes de abrir transacciones costosas.
       ============================================================================================ */
    
    /* 2.1 Validación de Identidad */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Estatus es inválido.';
    END IF;

    /* 2.2 Validación de Dominio (Solo 0 o 1) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El estatus solo puede ser 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* ============================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       El núcleo de la seguridad transaccional.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL REGISTRO (SNAPSHOT)
       - Buscamos el registro en `Cat_Estatus_Capacitacion`.
       - `FOR UPDATE`: Adquiere un candado de escritura (X-Lock) sobre la fila.
       - Efecto: Serializa la operación. Nadie más puede tocar este estatus hasta el COMMIT.
       -------------------------------------------------------------------------------------------- */
    SELECT 1, `Activo`, `Nombre` 
    INTO v_Existe, v_Activo_Actual, v_Nombre_Estatus
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA
       Si el SELECT anterior no encontró nada, v_Existe seguirá siendo NULL.
       -------------------------------------------------------------------------------------------- */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberar recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado no existe en el catálogo.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN "SIN CAMBIOS")
       - Lógica: "Si ya está encendido, no intentes encenderlo de nuevo".
       - Beneficio: Evita escrituras en disco y preserva el timestamp `updated_at`.
       -------------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente.
        
        /* Retornamos mensaje de éxito informativo */
        SELECT CONCAT('AVISO: El Estatus "', v_Nombre_Estatus, '" ya se encuentra en el estado solicitado.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Estatus AS Id_Estatus,
               _Nuevo_Estatus AS Nuevo_Estatus;
        
        LEAVE THIS_PROC; -- Salimos del procedimiento.
    END IF;

    /* ============================================================================================
       BLOQUE 4: REGLAS DE BLINDAJE (CANDADOS DE INTEGRIDAD)
       Solo ejecutamos esto si realmente vamos a cambiar el estado.
       ============================================================================================ */

    /* --------------------------------------------------------------------------------------------
       PASO 4.1: REGLA DE DESACTIVACIÓN (CANDADO DESCENDENTE)
       - Condición: Solo si `_Nuevo_Estatus = 0` (Intentamos apagar).
       - Objetivo: Evitar dejar capacitaciones "huérfanas" de estatus.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Reiniciamos el semáforo */
        SET v_Dependencias = NULL;

        /* [SONDEO DE DEPENDENCIAS]:
           Consultamos la tabla operativa `DatosCapacitaciones`.
           Buscamos si existe AL MENOS UNA fila que cumpla:
             1. Use este estatus (`Fk_Id_CatEstCap`).
             2. Esté VIVA (`Activo = 1`). No nos importan los registros históricos borrados.
        */
        SELECT 1 INTO v_Dependencias
        FROM `DatosCapacitaciones`
        WHERE `Fk_Id_CatEstCap` = _Id_Estatus
          AND `Activo` = 1
        LIMIT 1; 

        /* [DISPARADOR DE BLOQUEO]:
           Si `v_Dependencias` no es NULL, significa que encontramos un conflicto. */
        IF v_Dependencias IS NOT NULL THEN
            ROLLBACK; -- Cancelamos la operación.
            
            /* Retornamos un error 409 (Conflicto) claro para el usuario */
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: No se puede desactivar este Estatus porque existen CAPACITACIONES ACTIVAS asignadas a él. Primero debe cambiar el estatus de esas capacitaciones a otro valor.';
        END IF;

    END IF;

    /* ============================================================================================
       BLOQUE 5: PERSISTENCIA (EJECUCIÓN DEL CAMBIO)
       Si llegamos aquí, hemos pasado todas las validaciones. Es seguro escribir.
       ============================================================================================ */
    
    /* Ejecutamos el UPDATE físico en la tabla */
    UPDATE `Cat_Estatus_Capacitacion`
    SET 
        `Activo` = _Nuevo_Estatus,
        `updated_at` = NOW() -- Auditoría: Registramos el momento exacto del cambio.
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ============================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       ============================================================================================ */
    
    /* Confirmamos la transacción (Hacemos permanentes los cambios y liberamos locks) */
    COMMIT;

    /* Generamos la respuesta para el Frontend */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido REACTIVADO y está disponible para su uso.')
            ELSE CONCAT('ÉXITO: El Estatus "', v_Nombre_Estatus, '" ha sido DESACTIVADO (Baja Lógica).')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        _Id_Estatus AS Id_Estatus,
        _Nuevo_Estatus AS Nuevo_Estatus;

END$$

DELIMITER ;