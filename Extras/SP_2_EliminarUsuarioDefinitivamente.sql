/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarUsuarioDefinitivamente
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el mecanismo de "Destrucción Física" (Hard Delete) del sistema.
   A diferencia de la "Baja Lógica" (Desactivar), este procedimiento elimina permanentemente 
   los registros de la base de datos, liberando espacio y referencias.

   [CASO DE USO EXCLUSIVO]: 
   Diseñado estrictamente para la "Corrección de Errores Administrativos Inmediatos".
   Ejemplo: "El Admin creó un usuario duplicado por error hace 5 minutos y necesita borrarlo
   para volver a capturarlo limpio".
   
   [ADVERTENCIA]: 
   NO debe utilizarse para gestionar despidos, renuncias o jubilaciones. Para esos casos 
   debe usarse `SP_CambiarEstatusUsuario` (Historial Laboral).

   --------------------------------------------------------------------------------------------
   II. REGLAS DE SEGURIDAD E INTEGRIDAD (THE SAFETY NET)
   --------------------------------------------------------------------------------------------
   [RN-01] PROTOCOLO ANTI-SUICIDIO (SELF-DESTRUCTION PREVENTION):
      - Principio: "El sistema no debe permitir que el último administrador se elimine a sí mismo".
      - Regla: Un usuario autenticado no puede ejecutar este SP contra su propio ID.

   [RN-02] ANÁLISIS FORENSE DE INSTRUCTOR (OPERATIONAL FOOTPRINT):
      - Antes de borrar, el sistema escanea la tabla `DatosCapacitaciones`.
      - Si el usuario aparece como Instructor en CUALQUIER curso (Pasado, Presente o Futuro),
        la eliminación se bloquea.
      - Justificación: Borrar al instructor dejaría "cursos huérfanos" en los reportes históricos.

   [RN-03] ANÁLISIS FORENSE DE PARTICIPANTE (ACADEMIC FOOTPRINT):
      - El sistema escanea la tabla `Capacitaciones_Participantes`.
      - Si el usuario tiene registros de asistencia o calificación, se bloquea.
      - Justificación: Es ilegal destruir evidencia de capacitación de un empleado (Auditoría STPS).

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE ARCHITECTURE)
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID Destructiva con Bloqueo Pesimista (`FOR UPDATE`).
   - ORDEN DE EJECUCIÓN (CASCADE LOGIC):
      Debido a la restricción de llave foránea (`Fk_Id_InfoPersonal` en `Usuarios`), el borrado
      debe seguir un orden quirúrgico para evitar errores de Constraint `ON DELETE NO ACTION`:
        1. Eliminar Hijo (`Usuarios`).
        2. Eliminar Padre (`Info_Personal`).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarUsuarioDefinitivamente`$$

CREATE PROCEDURE `SP_EliminarUsuarioDefinitivamente`(
    IN _Id_Admin_Ejecutor    INT,   -- [AUDITOR] Quién ordena la ejecución (Logs de App)
    IN _Id_Usuario_Objetivo  INT    -- [TARGET] El usuario a eliminar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       ======================================================================================== */
    
    /* Punteros de Relación para el borrado en cascada */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL;
    DECLARE v_Ficha_Objetivo  VARCHAR(50);
    DECLARE v_Existe          INT;
    
    /* Banderas de Análisis Forense (Semáforos de Integridad) */
    DECLARE v_Es_Instructor   INT DEFAULT NULL;
    DECLARE v_Es_Participante INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       ======================================================================================== */
    /* Ante cualquier fallo técnico, aseguramos que la BD regrese a su estado original */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Integridad de Inputs */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de usuario inválido.';
    END IF;

    /* 2.2 Protección Anti-Suicidio (Seguridad Básica) */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes eliminarte a ti mismo. Por seguridad, pide a otro administrador que realice esta acción.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INSPECCIÓN Y BLOQUEO (FORENSIC ANALYSIS)
       Propósito: "Congelar" al usuario y verificar si tiene ataduras históricas antes de borrar.
       ======================================================================================== */
    START TRANSACTION;

    /* 3.1 Obtener datos base y aplicar CANDADO DE ESCRITURA (X-LOCK) */
    SELECT 
        1, `Fk_Id_InfoPersonal`, `Ficha`
    INTO 
        v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* Validación de Existencia */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe o ya fue eliminado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: ESCANEO DE HUELLA COMO INSTRUCTOR (Operational Trace)
       Buscamos si su ID aparece como Foreign Key en la tabla de Historial de Capacitaciones.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Instructor
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_Instructor` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Instructor IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario figura como INSTRUCTOR en el historial de capacitaciones. Use la opción "Desactivar" para archivar el expediente.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: ESCANEO DE HUELLA COMO ALUMNO (Academic Trace)
       Buscamos si su ID aparece en listas de asistencia/calificaciones.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Participante
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Participante IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario tiene historial académico como PARTICIPANTE (Calificaciones/Asistencia). Use la opción "Desactivar" para preservar la evidencia.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (HARD DELETE SEQUENCE)
       Si llegamos aquí, el usuario está "limpio" (no tiene historial operativo).
       Procedemos a borrar en el orden correcto para respetar las FKs.
       ======================================================================================== */
    
    /* 4.1 Eliminar Cuenta de Usuario (Entidad Hija)
       Primero borramos aquí para liberar la referencia `Fk_Id_InfoPersonal` */
    DELETE FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 4.2 Eliminar Datos Personales (Entidad Padre)
       Ahora que nadie lo referencia desde Usuarios, es seguro borrar sus datos demográficos. */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        DELETE FROM `Info_Personal` 
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN FINAL
       ======================================================================================== */
    COMMIT;

    /* Feedback de éxito para el Frontend */
    SELECT 
        CONCAT('ELIMINACIÓN EXITOSA: El usuario ', v_Ficha_Objetivo, ' y todos sus datos asociados han sido borrados permanentemente del sistema.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Eliminado,
        'ELIMINADO' AS Accion;

END$$

DELIMITER ;