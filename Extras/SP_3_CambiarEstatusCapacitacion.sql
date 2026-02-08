/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacion (TOGGLE SWITCH)_
   ====================================================================================================
   
   1. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------
   - Nombre Oficial:      SP_CambiarEstatusCapacitacion
   - Clasificación:       Transacción de Gobernanza de Ciclo de Vida (Lifecycle Governance Transaction).
   - Patrón de Diseño:    "Toggle Switch with State Validation & Audit Injection".
   - Criticidad:          ALTA (Afecta la visibilidad global del expediente en todo el sistema).
   - Nivel de Aislamiento: SERIALIZABLE (Implícito por el manejo de transacciones atómicas).

   2. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   --------------------------------------------------------------
   Este procedimiento actúa como el "Interruptor Maestro" del expediente. Su función no es eliminar datos
   (DELETE físico prohibido), sino alterar la disponibilidad lógica del curso (Soft Delete/Restore).
   
   [REGLAS DE ORO DEL ARCHIVADO - GOVERNANCE RULES]:
   
   A. PRINCIPIO DE FINALIZACIÓN (COMPLETION PRINCIPLE):
      - Regla: No se permite archivar un curso que está "Vivo" (En Progreso, Programado, Por Iniciar).
      - Mecanismo: El sistema exige que el curso haya llegado a un estado TERMINAL (Concluido, Cancelado, Deserto)
        antes de permitir su archivo. Esto se valida contra la bandera `Es_Final` del catálogo de estatus.
      - Justificación: Previene la desaparición accidental de cursos activos del Dashboard Operativo.
   
   B. PRINCIPIO DE CASCADA (CASCADE PRINCIPLE):
      - Regla: La acción de Archivar/Restaurar es atómica y jerárquica.
      - Mecanismo: Al apagar el Padre (`Capacitaciones`), se debe apagar forzosamente al Hijo vigente 
        (`DatosCapacitaciones`) para mantener la coherencia visual en las consultas `INNER JOIN`.

   C. ESTRATEGIA DE TRAZABILIDAD AUTOMÁTICA (AUDIT INJECTION):
      - Regla: Cada acción de archivado debe dejar una huella indeleble.
      - Mecanismo: Además de cambiar el bit `Activo`, se inyecta una "Nota de Sistema" en el campo 
        `Observaciones` del detalle operativo.
      - Texto Inyectado: "La capacitación con folio [X] de la Gerencia [Y] fue archivada automáticamente..."
      - Objetivo: Que cualquier auditor futuro sepa que esto no fue un accidente, sino un cierre de ciclo deliberado.

   3. ACTUALIZACIÓN DE METADATOS (TIMESTAMPS STRATEGY)
   ---------------------------------------------------
   Se actualizan las columnas `updated_at` y `Updated_by` (donde aplique) tanto en el Padre como en el Hijo
   para reflejar el momento exacto del cambio de estado, garantizando la integridad de la línea de tiempo.

   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacion`(
    /* --------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los identificadores mínimos necesarios para localizar y auditar la operación.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Capacitacion     INT, -- Identificador único del Expediente Maestro (Padre) a modificar.
    IN _Id_Usuario_Ejecutor INT  -- Identificador del usuario que acciona el interruptor (Auditoría).
)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Estas variables actúan como la memoria temporal para el diagnóstico del estado actual.
       -------------------------------------------------------------------------------------------- */
    
    /* Snapshot del Estado del Padre (¿Está activo o archivado?) */
    DECLARE v_Estado_Actual_Padre TINYINT(1); 
    
    /* Punteros al Hijo (Detalle Operativo) */
    DECLARE v_Id_Ultimo_Detalle INT;          
    DECLARE v_Id_Estatus_Actual INT;          
    
    /* Variable de Control de Negocio (Bandera de Seguridad obtenida del Catálogo) */
    DECLARE v_Es_Estatus_Final TINYINT(1);    -- 1 = Terminal (Archivable), 0 = Vivo (No Archivable)
    DECLARE v_Nombre_Estatus VARCHAR(50);     -- Nombre legible del estatus para mensajes de error.
    
    /* Variables para la construcción del Mensaje de Auditoría (Audit Log Construction) */
    DECLARE v_Folio VARCHAR(50);
    DECLARE v_Clave_Gerencia VARCHAR(50);
    DECLARE v_Mensaje_Auditoria TEXT;

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       Garantía de Atomicidad (ACID). Si cualquier paso de la actualización en cascada falla 
       (ej: error de disco, bloqueo de tabla), se revierten todos los cambios (ROLLBACK) para 
       evitar expedientes "zombies" (Padre activo / Hijo inactivo).
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       FASE 1: DIAGNÓSTICO Y RECUPERACIÓN DE CONTEXTO (PRE-FLIGHT CHECK)
       Antes de actuar, debemos "leer el terreno". Obtenemos todos los datos necesarios para 
       validar las reglas de negocio y construir el mensaje de log.
       ============================================================================================ */
    
    /* 1.1 Radiografía del Padre + Datos de la Gerencia (JOIN) */
    /* Obtenemos el estado global actual para decidir si vamos a ENCENDER o APAGAR. 
       También traemos el Folio y la Clave de Gerencia para la nota de auditoría. */
    SELECT 
        `Cap`.`Activo`, 
        `Cap`.`Numero_Capacitacion`,
        `Ger`.`Clave`
    INTO 
        v_Estado_Actual_Padre, 
        v_Folio,
        v_Clave_Gerencia
    FROM `Capacitaciones` `Cap`
    INNER JOIN `Cat_Gerencias_Activos` `Ger` ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    WHERE `Cap`.`Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

    /* Validación de Existencia (404 check) */
    /* Si la consulta no devolvió nada, detenemos la ejecución inmediatamente. */
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: El expediente de capacitación solicitado no existe.';
    END IF;

    /* 1.2 Radiografía del Hijo + BANDERA DE ESTATUS (JOIN CRÍTICO) */
    /* Necesitamos identificar cuál es la versión vigente y validar si su estatus permite el archivado.
       Usamos ORDER BY DESC LIMIT 1 para asegurar que obtenemos el último movimiento histórico. */
    SELECT 
        `DC`.`Id_DatosCap`, 
        `CatEst`.`Es_Final`,  -- <--- Leemos la bandera de seguridad directamente del catálogo
        `CatEst`.`Nombre`     -- <--- Leemos el nombre para mensajes de error claros
    INTO 
        v_Id_Ultimo_Detalle, 
        v_Es_Estatus_Final,
        v_Nombre_Estatus
    FROM `DatosCapacitaciones` `DC`
    /* JOIN para validar la regla de negocio contra el catálogo maestro */
    INNER JOIN `Cat_Estatus_Capacitacion` `CatEst` 
        ON `DC`.`Fk_Id_CatEstCap` = `CatEst`.`Id_CatEstCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion
    ORDER BY `DC`.`Id_DatosCap` DESC 
    LIMIT 1;

    /* ============================================================================================
       FASE 2: MOTOR DE DECISIÓN LÓGICA (THE SWITCH CORE)
       Aquí se bifurca el flujo dependiendo de si queremos Archivar (Turn OFF) o Restaurar (Turn ON).
       ============================================================================================ */
    START TRANSACTION;

    /* [CASO A]: INTENTO DE ARCHIVADO (APAGADO) 
       Se ejecuta si el expediente está actualmente ACTIVO (1). */
    IF v_Estado_Actual_Padre = 1 THEN
        
        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.A.1: VALIDACIÓN DE REGLAS DE NEGOCIO (SAFETY LOCK)
           Objetivo: Prevenir el archivado de cursos vivos.
           Verificamos la bandera `Es_Final` obtenida en la Fase 1.
           ---------------------------------------------------------------------------------------- */
        
        /* [BLOQUEO DE SEGURIDAD]: Si el estatus NO es final (ej: Es_Final = 0), ABORTAMOS. */
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
            ROLLBACK;
            
            -- Construimos un mensaje de error dinámico y específico para guiar al usuario
            SET @ErrorMsg = CONCAT(
                'ACCIÓN DENEGADA [409]: No se puede archivar un curso activo. ',
                'El estatus actual es "', v_Nombre_Estatus, '", el cual se considera OPERATIVO (No Final). ',
                'Debe finalizar o cancelar la capacitación antes de archivarla.'
            );
            
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
        END IF;

        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.A.2: CONSTRUCCIÓN DE EVIDENCIA FORENSE (AUDIT LOGGING)
           Preparamos el mensaje que se inyectará permanentemente en el registro.
           ---------------------------------------------------------------------------------------- */
        SET v_Mensaje_Auditoria = CONCAT(
            ' [SISTEMA]: La capacitación con folio ', v_Folio, 
            ' de la Gerencia ', v_Clave_Gerencia, 
            ', fue archivada el ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
            ' porque alcanzó el fin de su ciclo de vida. Si fue un error, favor de reactivar manualmente.'
        );

        /* ----------------------------------------------------------------------------------------
           SUB-FASE 2.A.3: EJECUCIÓN DEL APAGADO EN CASCADA (SOFT DELETE CASCADE)
           Procedemos a desactivar jerárquicamente y registrar la auditoría.
           ---------------------------------------------------------------------------------------- */
        
        /* 1. Apagado del Padre (Nivel Expediente) */
        /* Se registra quién hizo el cierre en `Updated_by` y la fecha actual. */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 0, 
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* 2. Apagado del Hijo (Nivel Versión) e INYECCIÓN DE NOTA */
        /* Esto oculta el detalle de las vistas operativas y anexa la justificación. */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 0, 
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW(),
            /* CONCAT_WS: Función segura que maneja NULLs. Agrega 2 saltos de línea antes de la nota. */
            `Observaciones` = CONCAT_WS('\n\n', `Observaciones`, v_Mensaje_Auditoria)
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* Confirmación de Transacción */
        COMMIT;
        
        /* Retorno de Feedback al Usuario */
        SELECT 'ARCHIVADO' AS `Nuevo_Estado`, 'Expediente archivado y nota de auditoría registrada.' AS `Mensaje`;

    /* [CASO B]: INTENTO DE RESTAURACIÓN (ENCENDIDO) 
       Se ejecuta si el expediente está actualmente INACTIVO (0). */
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
        /* Restauramos la visibilidad de la última versión conocida para que vuelva a aparecer en el Grid.
           Nota: Aquí NO inyectamos texto, solo actualizamos el timestamp. */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 1, 
			`Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor, 
            `updated_at` = NOW()
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* Confirmación de Transacción */
        COMMIT;

        /* Retorno de Feedback al Usuario */
        SELECT 'RESTAURADO' AS `Nuevo_Estado`, 'Expediente restaurado exitosamente.' AS `Mensaje`;

    END IF;

END$$

DELIMITER ;