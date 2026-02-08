/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusUsuario
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor central de "Gestión de Acceso y Disponibilidad" (Lifecycle Manager).
   Administra el ciclo de vida de un usuario mediante el mecanismo de BAJA LÓGICA (Soft Delete).

   [PROBLEMA DE INTEGRIDAD OPERATIVA]:
   En un sistema de gestión de capacitación, "Desactivar" a un usuario no es solo impedir que
   inicie sesión. Si desactivamos a un instructor que tiene un curso programado para mañana,
   estamos creando un "Evento Acéfalo" (Curso sin maestro), lo cual es un fallo grave de servicio.

   [SOLUCIÓN IMPLEMENTADA]:
   Este SP actúa como un guardián inteligente que:
   1. Verifica si el usuario tiene "deudas operativas" (cursos activos) antes de permitir su baja.
   2. Sincroniza el estado de bloqueo tanto en su cuenta de acceso (`Usuarios`) como en su
      perfil de recursos humanos (`Info_Personal`) para mantener coherencia en los reportes.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (SECURITY & BUSINESS RULES)
   --------------------------------------------------------------------------------------------
   [RN-01] PROTOCOLO ANTI-LOCKOUT (SEGURIDAD):
      - Principio: "No puedes encerrarte a ti mismo fuera de casa y tirar la llave".
      - Regla: Un Administrador tiene prohibido desactivar su propia cuenta.

   [RN-02] INTEGRIDAD SINCRONIZADA (DATA CONSISTENCY):
      - El cambio de estatus es atómico: O se desactivan AMBAS tablas (`Usuarios` e `Info_Personal`)
        o no se desactiva ninguna. Esto evita que un usuario bloqueado siga apareciendo 
        en las listas desplegables de selección de instructores.

   [RN-03] CANDADO OPERATIVO (THE GOLDEN RULE):
      - Definición: "No se puede retirar al personal esencial en medio de una operación".
	  - Lógica: Si se intenta DESACTIVAR (0), el sistema escanea DOS frentes:
		
        A) ROL INSTRUCTOR (`DatosCapacitaciones`):
      - Estatus Bloqueantes (Conflictos):
          * 1 (PROGRAMADO) y 9 (REPROGRAMADO): Compromiso futuro confirmado.
          * 2 (POR INICIAR): Inminencia operativa.
          * 3 (EN CURSO): Ejecución en tiempo real.
          * 5 (EN EVALUACIÓN): Proceso administrativo pendiente de cierre.

		B) ROL PARTICIPANTE (`Capacitaciones_Participantes`):
           * Bloquea si tiene estatus: 1 (PROGRAMADO) o 2 (EN CURSO).
             (Nota: Permite baja si ya acreditó, reprobó o canceló).

      - Acción: Si se detecta CUALQUIERA de estos, la operación se ABORTA con un error 409.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento Serializable (Row-Level Locking).
   - ESTRATEGIA: Bloqueo Pesimista (`FOR UPDATE`) para evitar condiciones de carrera durante
     la verificación de cursos activos.
   ============================================================================================ */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_CambiarEstatusUsuario`$$

CREATE PROCEDURE `SP_CambiarEstatusUsuario`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,        -- [AUDITOR] Quién realiza la acción
    IN _Id_Usuario_Objetivo  INT,        -- [TARGET] A quién se desactiva/activa
    IN _Nuevo_Estatus        TINYINT     -- [FLAG] 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       ======================================================================================== */
    
    /* Punteros de Relación para la sincronización en cascada */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL;
    DECLARE v_Ficha_Objetivo  VARCHAR(50);
    
    /* Snapshot de Estado para verificación de Idempotencia */
    DECLARE v_Estatus_Actual  TINYINT(1);
    DECLARE v_Existe          INT;
    
    /* Variables de Diagnóstico para el Candado Operativo */
    DECLARE v_Curso_Conflictivo VARCHAR(50) DEFAULT NULL; 
    DECLARE v_Estatus_Conflicto VARCHAR(255) DEFAULT NULL;
    DECLARE v_Rol_Conflicto     VARCHAR(50) DEFAULT NULL; -- [NUEVO] Distingue entre Instructor vs Participante

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       ======================================================================================== */
    
    /* Handler Genérico: Ante cualquier fallo SQL, garantiza el Rollback */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Integridad de Identificadores */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Usuario_Objetivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: IDs inválidos.';
    END IF;

    /* 2.2 Validación de Dominio (Binario) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DATOS [400]: El estatus debe ser 1 o 0.';
    END IF;

    /* 2.3 Regla Anti-Lockout (Seguridad) */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes desactivar tu propia cuenta. Por seguridad, solicita a otro administrador.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CANDADO OPERATIVO (INTEGRACIÓN CON MÓDULO DE CAPACITACIÓN)
       Propósito: Validar que el usuario no sea esencial para operaciones vivas.
       Condición: Solo se ejecuta si la intención es APAGAR (0) al usuario.
       ======================================================================================== */
    IF _Nuevo_Estatus = 0 THEN
        
        /* ------------------------------------------------------------------------------------
           3.1 VERIFICACIÓN DE ROL: INSTRUCTOR
           [REGLA]: No se puede retirar a un instructor si tiene cursos "vivos" asignados.
           ------------------------------------------------------------------------------------ */
        SELECT 
            C.Numero_Capacitacion,
            EC.Nombre,
            'INSTRUCTOR'
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `DatosCapacitaciones` DC
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            DC.Fk_Id_Instructor = _Id_Usuario_Objetivo
            AND DC.Activo = 1 
            /* Estatus Bloqueantes: 1=Programado, 2=Por Iniciar, 3=En Curso, 5=En Evaluación, 9=Reprogramado */
            AND DC.Fk_Id_CatEstCap IN (1, 2, 3, 5, 9) 
        LIMIT 1;

        /* Si es Instructor Activo -> ERROR 409 */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar. El usuario es INSTRUCTOR en el curso "', v_Curso_Conflictivo, '" (Estatus: ', v_Estatus_Conflicto, '). Debe reasignar el curso o cancelarlo antes de proceder.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

        /* ------------------------------------------------------------------------------------
           3.2 VERIFICACIÓN DE ROL: PARTICIPANTE [NUEVA REGLA DE BLINDAJE]
           [REGLA]: No se puede retirar a un alumno si está inscrito en un curso vigente.
           Esto evita inconsistencias en listas de asistencia y actas de calificación.
           ------------------------------------------------------------------------------------ */
        SELECT 
            C.Numero_Capacitacion,
            EP.Nombre,
            'PARTICIPANTE'
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `Capacitaciones_Participantes` CP
        INNER JOIN `DatosCapacitaciones` DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        INNER JOIN `Cat_Estatus_Participante` EP ON CP.Fk_Id_CatEstPart = EP.Id_CatEstPart
        WHERE 
            CP.Fk_Id_Usuario = _Id_Usuario_Objetivo
            /* [CRÍTICO]: Solo bloqueamos si está PROGRAMADO (1) o EN CURSO (2).
               Si ya Acreditó (3), No Acreditó (4) o fue Cancelado (5), es historia y se permite la baja. */
            AND CP.Fk_Id_CatEstPart IN (1, 2)
        LIMIT 1;

        /* Si es Participante Activo -> ERROR 409 */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar. El usuario es PARTICIPANTE activo en el curso "', v_Curso_Conflictivo, '" (Estatus: ', v_Estatus_Conflicto, '). Debe finalizar su participación o darlo de baja del curso primero.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ========================================================================================
       BLOQUE 4: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       Propósito: Aislar al usuario para aplicar el cambio de estado de forma segura.
       ======================================================================================== */
    START TRANSACTION;

    /* Adquisición de Snapshot y Bloqueo de Fila */
    SELECT 1, `Fk_Id_InfoPersonal`, `Ficha`, `Activo`
    INTO v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo, v_Estatus_Actual
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* Validación de Existencia */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe.';
    END IF;

    /* Verificación de Idempotencia ("Sin Cambios") 
       Si el estado actual ya es igual al nuevo, ahorramos el UPDATE y el Log. */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('SIN CAMBIOS: El usuario ya estaba ', IF(_Nuevo_Estatus=1, 'ACTIVO', 'INACTIVO')) AS Mensaje,
               _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA SINCRONIZADA (CASCADE UPDATE)
       Propósito: Mantener la coherencia entre el Acceso (Usuarios) y la Operación (InfoPersonal).
       ======================================================================================== */
    
    /* 5.1 Desactivar Acceso (Login/Sistema) */
    UPDATE `Usuarios`
    SET `Activo` = _Nuevo_Estatus,
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 5.2 Desactivar Operatividad (Recursos Humanos)
       Esto asegura que el usuario desaparezca de los selectores de "Instructores Disponibles" */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        UPDATE `Info_Personal`
        SET `Activo` = _Nuevo_Estatus,
            `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
            `updated_at` = NOW()
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    COMMIT;

    /* Feedback claro para el Frontend */
    SELECT 
        CONCAT('ÉXITO: Usuario ', v_Ficha_Objetivo, IF(_Nuevo_Estatus=1, ' REACTIVADO', ' DESACTIVADO'), '.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        IF(_Nuevo_Estatus=1, 'ACTIVADO', 'DESACTIVADO') AS Accion;

END$$

DELIMITER ;