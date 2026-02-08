/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacion (TOGGLE SWITCH)
   ====================================================================================================
   
   1. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------
   - Nombre Oficial:      SP_CambiarEstatusCapacitacion
   - Clasificación:       Transacción de Gobernanza de Ciclo de Vida (Lifecycle Governance Transaction).
   - Patrón de Diseño:    "Toggle Switch with State Validation" (Interruptor con Validación de Estado).
   - Nivel de Impacto:    GLOBAL (Afecta la visibilidad del expediente en todo el sistema).

   2. PROPÓSITO FORENSE Y DE NEGOCIO
   ---------------------------------
   Este procedimiento actúa como el "Interruptor Maestro" del expediente. Su función no es eliminar datos
   (DELETE físico prohibido), sino alterar la disponibilidad lógica del curso (Soft Delete/Restore).
   
   [REGLAS DE ORO DEL ARCHIVADO]:
   A. PRINCIPIO DE FINALIZACIÓN: No se permite archivar un curso que está "Vivo" (En Progreso, Programado).
      El sistema exige que el curso haya llegado a un estado terminal (Concluido, Cancelado) antes de
      permitir su archivo. Esto previene la desaparición accidental de cursos activos del Dashboard.
   
   B. PRINCIPIO DE CASCADA: La acción de Archivar/Restaurar es atómica y jerárquica. Al apagar el Padre
      (Capacitación), se debe apagar forzosamente al Hijo vigente (Detalle) para mantener la coherencia
      visual en las consultas `INNER JOIN`.

   3. ARQUITECTURA DE VALIDACIÓN
   -----------------------------
   Utiliza una bandera de control (`Es_Final`) alojada en el catálogo `Cat_Estatus_Capacitacion`.
   - Si Es_Final = 0 (Operativo): El bloqueo de seguridad IMPIDE el archivado.
   - Si Es_Final = 1 (Terminal): El bloqueo se libera y permite el archivado.
   
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       -------------------------------------------------------------------------------------------- */
    IN _Id_Capacitacion     INT, -- Identificador único del Expediente Maestro (Padre) a modificar.
    IN _Id_Usuario_Ejecutor INT  -- Identificador del usuario que acciona el interruptor (Auditoría).
)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Estas variables actúan como la memoria temporal para el diagnóstico del estado actual.
       -------------------------------------------------------------------------------------------- */
    DECLARE v_Estado_Actual_Padre TINYINT(1); -- Almacena si el curso está actualmente Activo (1) o Archivado (0).
    DECLARE v_Id_Ultimo_Detalle INT;          -- Puntero al registro hijo más reciente (la versión vigente).
    DECLARE v_Id_Estatus_Actual INT;          -- ID del estatus operativo actual (ej: 4=Finalizado, 2=En Curso).
    DECLARE v_Es_Estatus_Final TINYINT(1);    -- Bandera de seguridad obtenida del catálogo (1=Se puede archivar).
    DECLARE v_Folio VARCHAR(50);              -- Dato descriptivo para el mensaje de retorno.

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       Garantía de Atomicidad (ACID). Si cualquier paso de la actualización en cascada falla,
       se revierten todos los cambios para evitar expedientes "zombies" (Padre activo / Hijo inactivo).
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       FASE 1: DIAGNÓSTICO DEL ESTADO ACTUAL (STATE DIAGNOSIS)
       Antes de actuar, debemos entender la situación del expediente. Leemos sin bloquear.
       ============================================================================================ */
    
    /* 1.1 Radiografía del Padre */
    /* Obtenemos el estado global actual para decidir si vamos a ENCENDER o APAGAR. */
    SELECT `Activo`, `Numero_Capacitacion` 
    INTO v_Estado_Actual_Padre, v_Folio
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

    /* Validación de Existencia (404 check) */
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: El expediente de capacitación solicitado no existe.';
    END IF;

    /* 1.2 Radiografía del Hijo (Última Versión) */
    /* Necesitamos identificar cuál es la versión vigente para aplicarle el mismo destino que al padre.
       Usamos ORDER BY DESC LIMIT 1 para asegurar que obtenemos el último movimiento histórico. */
    SELECT `Id_DatosCap`, `Fk_Id_CatEstCap`
    INTO v_Id_Ultimo_Detalle, v_Id_Estatus_Actual
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_Capacitacion` = _Id_Capacitacion
    ORDER BY `Id_DatosCap` DESC 
    LIMIT 1;

    /* ============================================================================================
       FASE 2: ÁRBOL DE DECISIÓN LÓGICA (THE SWITCH CORE)
       Aquí se bifurca el flujo dependiendo de si queremos Archivar o Restaurar.
       ============================================================================================ */
    START TRANSACTION;

    /* CASO A: EL EXPEDIENTE ESTÁ ACTIVO (1) -> INTENTO DE ARCHIVADO (APAGADO) */
    IF v_Estado_Actual_Padre = 1 THEN
        
        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.A.1: VERIFICACIÓN DE REGLAS DE NEGOCIO (SAFETY LOCK)
           Objetivo: Prevenir el archivado de cursos vivos.
           Consultamos el catálogo de estatus para ver si el estado actual permite cierre.
           ---------------------------------------------------------------------------------------- */
        SELECT `Es_Final` INTO v_Es_Estatus_Final
        FROM `Cat_Estatus_Capacitacion`
        WHERE `Id_CatEstCap` = v_Id_Estatus_Actual;

        /* [BLOQUEO DE SEGURIDAD]: Si el estatus no es final (ej: Es_Final = 0), ABORTAMOS. */
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Violación de Regla de Negocio. No se puede archivar una capacitación activa o en progreso. Debe cambiar el estatus a uno TERMINAL (Concluido/Cancelado) antes de archivar.';
        END IF;

        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.A.2: EJECUCIÓN DEL APAGADO EN CASCADA (SOFT DELETE CASCADE)
           Procedemos a desactivar jerárquicamente.
           ---------------------------------------------------------------------------------------- */
        
        /* 1. Apagado del Padre (Nivel Expediente) */
        /* Se registra quién hizo el cierre en `Updated_by` */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 0, 
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* 2. Apagado del Hijo (Nivel Versión) */
        /* Esto oculta el detalle de las vistas operativas */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 0, 
            `updated_at` = NOW() 
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* Confirmación de Transacción */
        COMMIT;
        
        /* Retorno de Feedback al Usuario */
        SELECT 
            'ARCHIVADO' AS `Nuevo_Estado_Logico`,
            CONCAT('El expediente ', v_Folio, ' ha sido archivado exitosamente y retirado de la vista principal.') AS `Mensaje_Sistema`;

    /* CASO B: EL EXPEDIENTE ESTÁ INACTIVO (0) -> INTENTO DE RESTAURACIÓN (ENCENDIDO) */
    ELSE
        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.B.1: EJECUCIÓN DE RESTAURACIÓN (ADMINISTRATIVE OVERRIDE)
           En este flujo NO validamos el estatus. Asumimos que si está archivado y se quiere 
           abrir, es una corrección administrativa legítima.
           ---------------------------------------------------------------------------------------- */
        
        /* 1. Encendido del Padre */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 1, 
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* 2. Encendido del Hijo */
        /* Restauramos la visibilidad de la última versión conocida para que vuelva a aparecer en el Grid */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 1, 
            `updated_at` = NOW()
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* Confirmación de Transacción */
        COMMIT;

        /* Retorno de Feedback al Usuario */
        SELECT 
            'RESTAURADO' AS `Nuevo_Estado_Logico`,
            CONCAT('El expediente ', v_Folio, ' ha sido restaurado. Ya es visible nuevamente en el Dashboard.') AS `Mensaje_Sistema`;

    END IF;

END$$

DELIMITER ;