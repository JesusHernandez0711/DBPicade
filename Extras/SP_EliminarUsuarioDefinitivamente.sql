/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarUsuarioDefinitivamente
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y RIESGO (THE "WHAT")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Mecanismo de "Destrucción Física" (Hard Delete). Elimina permanentemente los registros 
   de las tablas `Usuarios` (Credenciales) e `Info_Personal` (Datos Humanos).

   [CASO DE USO]: 
   Exclusivo para corrección de errores administrativos inmediatos.
   Ejemplo: "Creé al usuario Juan, me equivoqué en todo, y quiero borrarlo para hacerlo de nuevo".
   
   NO debe usarse para empleados que renunciaron (para eso es la Baja Lógica).

   --------------------------------------------------------------------------------------------
   II. REGLAS DE NEGOCIO (THE SAFETY NET)
   --------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD OPERATIVA (HUELLA DE INSTRUCTOR):
      - Validación: Se escanea la tabla `DatosCapacitaciones`.
      - Regla: Si el usuario ha sido Instructor en CUALQUIER curso (Histórico o Vigente), 
        la eliminación se bloquea.
      - Justificación: Borrar al instructor dejaría cursos históricos sin responsable.

   [RN-02] INTEGRIDAD ACADÉMICA (HUELLA DE PARTICIPANTE):
      - Validación: Se escanea la tabla `Capacitaciones_Participantes`.
      - Regla: Si el usuario tiene registros de asistencia o calificación, se bloquea.
      - Justificación: Es ilegal destruir evidencia de capacitación de un empleado.

   [RN-03] ORDEN DE EJECUCIÓN (DATABASE CONSTRAINTS):
      - Debido a la llave foránea `Fk_Id_InfoPersonal` en la tabla `Usuarios`, el orden 
        de borrado es estricto:
        1. Eliminar Hijo (`Usuarios`).
        2. Eliminar Padre (`Info_Personal`).

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID Destructiva.
   - AUDITORÍA: Al ser borrado físico, no queda rastro en BD. El log debe quedar en el Backend.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarUsuarioDefinitivamente`$$

CREATE PROCEDURE `SP_EliminarUsuarioDefinitivamente`(
    IN _Id_Admin_Ejecutor    INT,   -- Quién ordena la ejecución (Para logs de aplicación)
    IN _Id_Usuario_Objetivo  INT    -- El usuario a eliminar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO
       ======================================================================================== */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL;
    DECLARE v_Ficha_Objetivo  VARCHAR(50);
    DECLARE v_Existe          INT;
    
    /* Banderas de Análisis Forense */
    DECLARE v_Es_Instructor   INT DEFAULT NULL;
    DECLARE v_Es_Participante INT DEFAULT NULL;

    /* Handler de Errores */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 1: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 1.1 Integridad de Inputs */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de usuario inválido.';
    END IF;

    /* 1.2 Protección Anti-Suicidio (Seguridad Básica) */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes eliminarte a ti mismo. Pide a otro administrador que lo haga.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: INSPECCIÓN Y BLOQUEO (FORENSIC ANALYSIS)
       Antes de intentar borrar, verificamos si "el cuerpo tiene ataduras".
       ======================================================================================== */
    START TRANSACTION;

    /* 2.1 Obtener datos base y bloquear fila */
    SELECT 
        1, `Fk_Id_InfoPersonal`, `Ficha`
    INTO 
        v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2.2: ESCANEO DE HUELLA COMO INSTRUCTOR (DatosCapacitaciones)
       Buscamos si su ID aparece como FK en algún curso.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Instructor
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_Instructor` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Instructor IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario figura como INSTRUCTOR en el historial de capacitaciones. Use la opción "Desactivar" para archivar.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2.3: ESCANEO DE HUELLA COMO ALUMNO (Capacitaciones_Participantes)
       Buscamos si su ID aparece en listas de asistencia.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Participante
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Participante IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario tiene historial académico como PARTICIPANTE (Calificaciones/Asistencia). Use la opción "Desactivar".';
    END IF;

    /* ========================================================================================
       BLOQUE 3: EJECUCIÓN DESTRUCTIVA (HARD DELETE)
       Si llegamos aquí, el usuario está "limpio" (no tiene historial operativo).
       ======================================================================================== */
    
    /* 3.1 Eliminar Cuenta de Usuario (Hijo)
       Primero borramos aquí para liberar la FK `Fk_Id_InfoPersonal` */
    DELETE FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 3.2 Eliminar Datos Personales (Padre)
       Ahora que nadie lo referencia desde Usuarios, podemos borrar sus datos personales. */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        DELETE FROM `Info_Personal` 
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 4: CONFIRMACIÓN FINAL
       ======================================================================================== */
    COMMIT;

    SELECT 
        CONCAT('ELIMINACIÓN EXITOSA: El usuario ', v_Ficha_Objetivo, ' y todos sus datos han sido borrados permanentemente del sistema.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Eliminado,
        'ELIMINADO' AS Accion;

END$$

DELIMITER ;