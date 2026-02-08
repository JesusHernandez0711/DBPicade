
/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusTemaCapacitacion
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO Y PROPÓSITO DEL NEGOCIO (THE "WHAT" & "WHY")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el mecanismo de control de ciclo de vida para los "Temas de Capacitación" (Cursos).
   Permite alternar entre dos estados operativos:
     - ACTIVO (1): El curso es visible y seleccionable para nuevas programaciones.
     - INACTIVO (0): El curso se oculta (Baja Lógica) pero se preserva para auditoría histórica.

   [EL PROBLEMA DE LA INTEGRIDAD OPERATIVA]:
   No podemos retirar del catálogo un curso que se va a impartir mañana (Programado) o que se
   está impartiendo hoy (En Curso). Hacerlo dejaría a la operación sin referencia válida.
   
   Sin embargo, SÍ debemos permitir retirar cursos obsoletos que ya fueron impartidos en el 
   pasado (Finalizados), para limpiar el catálogo sin perder el historial.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (KILL SWITCHES INTELIGENTES)
   --------------------------------------------------------------------------------------------
   
   [RN-01] CANDADO DE DEPENDENCIA OPERATIVA (AL DESACTIVAR):
      - Definición: "Solo se puede archivar lo que no está en uso activo".
      - Lógica: Si se intenta DESACTIVAR (0), el sistema escanea `DatosCapacitaciones`.
      - Estatus Bloqueantes (Conflictos):
          * 1 (PROGRAMADO): Compromiso futuro.
          * 2 (POR INICIAR): Inminencia operativa.
          * 3 (EN CURSO): Ejecución en tiempo real.
          * 5 (EN EVALUACIÓN): Proceso administrativo pendiente.
          * 9 (REPROGRAMADO): Compromiso reagendado.
      - Estatus NO Bloqueantes (Permitidos):
          * 4 (FINALIZADO), 6 (CANCELADO), 7 (SUSPENDIDO), 8 (DESERTO).
      
      - Acción: Si se detecta un curso en estatus bloqueante, se ABORTA con error 409.

   [RN-02] CANDADO JERÁRQUICO (AL REACTIVAR):
      - Regla: "Un hijo no puede vivir si el padre está muerto".
      - Acción: Si se intenta REACTIVAR (1), verificamos que el `Tipo de Instrucción` (Padre)
        esté ACTIVO. Si no, se bloquea.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento Serializable.
   - ESTRATEGIA: Bloqueo Pesimista (`FOR UPDATE`) para evitar condiciones de carrera.
   ============================================================================================ */

DELIMITER $$

 DROP PROCEDURE IF EXISTS `SP_CambiarEstatusTemaCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusTemaCapacitacion`(
    IN _Id_Tema       INT,       -- [OBLIGATORIO] El Curso a modificar (PK)
    IN _Nuevo_Estatus TINYINT    -- [OBLIGATORIO] 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ENTORNO
       ======================================================================================== */
    /* Snapshot del estado actual */
    DECLARE v_Activo_Actual TINYINT DEFAULT NULL;
    DECLARE v_Nombre_Tema   VARCHAR(255) DEFAULT NULL;
    DECLARE v_Id_TipoInst   INT DEFAULT NULL;
    
    /* Variables para validaciones */
    DECLARE v_Tipo_Activo        TINYINT DEFAULT NULL;
    
    /* Variables de Diagnóstico Operativo */
    DECLARE v_Curso_Conflictivo  VARCHAR(50) DEFAULT NULL;
    DECLARE v_Estatus_Conflicto  VARCHAR(255) DEFAULT NULL;
    -- DECLARE v_Descripcion_Estatus VARCHAR(255) DEFAULT NULL;
    
    /* ========================================================================================
       BLOQUE 1: HANDLERS (SEGURIDAD TÉCNICA)
       ======================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;
    
    /* ========================================================================================
       BLOQUE 2: VALIDACIONES BÁSICAS (FAIL FAST)
       ======================================================================================== */
    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Tema inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El estatus solo puede ser 0 o 1.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO OPERATIVO (INTEGRACIÓN CON CAPACITACIONES)
       Propósito: Validar que el tema no sea esencial para operaciones VIVAS.
       Condición: Solo se ejecuta si la intención es APAGAR (0) el tema.
       ======================================================================================== */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Buscamos si existe alguna capacitación VIGENTE que use este tema y esté en una fase activa.
           Usamos JOINs para obtener nombres legibles para el error. */
        
        SELECT 
            C.Numero_Capacitacion,
            EC.Nombre -- Nombre del Estatus (ej: "EN CURSO")
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto
        FROM `Capacitaciones` C
        /* Unimos con DatosCapacitaciones para ver el estatus real */
        INNER JOIN `DatosCapacitaciones` DC ON C.Id_Capacitacion = DC.Fk_Id_Capacitacion
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            C.Fk_Id_Cat_TemasCap = _Id_Tema
            AND C.Activo = 1  -- La capacitación en sí está activa
            AND DC.Activo = 1 -- El registro de detalle es el vigente
            /* LISTA NEGRA DE ESTATUS (NO SE PUEDE BORRAR SI ESTÁ AQUÍ):
               1 = Programado
               2 = Por Iniciar
               3 = En Curso
               5 = En Evaluación
               9 = Reprogramado */
            -- AND DC.Fk_Id_CatEstCap IN (1, 2, 3, 5, 9)
            /* --- AQUÍ ESTÁ EL CAMBIO MAESTRO --- */
            AND EC.Es_Final = 0 -- Buscamos SOLO estatus que NO sean finales (Vivos)
        LIMIT 1;

        /* Si encontramos un conflicto, abortamos con un mensaje claro 
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar el Tema. Está asignado a la capacitación activa "', v_Curso_Conflictivo, '" que se encuentra "', v_Estatus_Conflicto, '". Debe cancelar o finalizar esa capacitación primero.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;*/

		/* Si encontramos un conflicto, abortamos con un mensaje claro */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar el Tema. Está asignado a la capacitación activa "', v_Curso_Conflictivo, '" que se encuentra "', v_Estatus_Conflicto, '". Este estatus se considera operativo (No Final). Debe finalizar o cancelar esa capacitación primero.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ========================================================================================
       BLOQUE 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: LEER Y BLOQUEAR EL REGISTRO
       ----------------------------------------------------------------------------------------
       Adquirimos un "Write Lock" sobre la fila. Esto asegura serialización. */
    
    SELECT `Activo`, `Nombre`, `Fk_Id_CatTipoInstCap`
    INTO v_Activo_Actual, v_Nombre_Tema, v_Id_TipoInst
    FROM `Cat_Temas_Capacitacion`
    WHERE `Id_Cat_TemasCap` = _Id_Tema
    FOR UPDATE;

    /* Si no se encuentra, abortamos */
    IF v_Activo_Actual IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Tema solicitado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: IDEMPOTENCIA (SIN CAMBIOS)
       ---------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('AVISO: El Tema "', v_Nombre_Tema, '" ya se encuentra en el estado solicitado.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               _Id_Tema AS Id_Tema,
               _Nuevo_Estatus AS Nuevo_Estatus;
        
        LEAVE THIS_PROC; 
    END IF;

    /* ========================================================================================
       BLOQUE 5: VALIDACIÓN JERÁRQUICA (SOLO AL REACTIVAR)
       ======================================================================================== */
    IF _Nuevo_Estatus = 1 THEN
        
        /* Solo validamos si tiene un Tipo asignado (no es huérfano) */
        IF v_Id_TipoInst IS NOT NULL THEN
            
            SELECT `Activo` INTO v_Tipo_Activo
            FROM `Cat_Tipos_Instruccion_Cap`
            WHERE `Id_CatTipoInstCap` = v_Id_TipoInst;

            /* Si el padre está inactivo, prohibimos la reactivación del hijo */
            IF v_Tipo_Activo = 0 THEN
                ROLLBACK;
                SELECT 'ERROR DE INTEGRIDAD: No se puede activar este Curso porque su "Tipo de Instrucción" está INACTIVO. Reactive la categoría primero.' AS Mensaje,
                       'ERROR_JERARQUIA' AS Accion,
                       _Id_Tema AS Id_Tema,
                       0 AS Nuevo_Estatus;
                LEAVE THIS_PROC;
            END IF;
        END IF;
    END IF;

/*
	IF _Nuevo_Estatus = 1 THEN
        
        IF v_Id_TipoInst IS NOT NULL THEN
            
            SELECT `Activo` INTO v_Tipo_Activo
            FROM `Cat_Tipos_Instruccion_Cap`
            WHERE `Id_CatTipoInstCap` = v_Id_TipoInst;

             Si el padre está inactivo (0), se LANZA ERROR para detener el flujo 
            IF v_Tipo_Activo = 0 THEN
                ROLLBACK;
                SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: No se puede reactivar este Tema porque su Categoría Padre (Tipo de Instrucción) está INACTIVA. Reactive la categoría primero.';
            END IF;
        END IF;
    END IF;*/

    /* ========================================================================================
       BLOQUE 6: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    UPDATE `Cat_Temas_Capacitacion`
    SET 
        `Activo`     = _Nuevo_Estatus,
        `updated_at` = NOW()
    WHERE 
        `Id_Cat_TemasCap` = _Id_Tema;

    /* ========================================================================================
       BLOQUE 7: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    COMMIT;

    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Tema "', v_Nombre_Tema, '" ha sido REACTIVADO.')
            ELSE CONCAT('ÉXITO: El Tema "', v_Nombre_Tema, '" ha sido DESACTIVADO (Archivado).')
        END AS Mensaje,
        
        'ESTATUS_MODIFICADO' AS Accion,
        _Id_Tema AS Id_Tema,
        _Nuevo_Estatus AS Nuevo_Estatus;

END$$

DELIMITER ;