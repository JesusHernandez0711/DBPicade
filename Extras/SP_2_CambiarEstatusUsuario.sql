/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusUsuario
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Motor de gestión de acceso (Baja Lógica) para usuarios del sistema.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE NEGOCIO (EL BLINDAJE)
   --------------------------------------------------------------------------------------------
   [RN-01] ANTI-LOCKOUT: 
      Un Administrador no puede desactivarse a sí mismo.

   [RN-02] INTEGRIDAD SINCRONIZADA: 
      El cambio de estatus se replica en `Usuarios` (Login) y `Info_Personal` (Operación).

   [RN-03] CANDADO OPERATIVO (CURSOS VIGENTES):
      - Si se intenta DESACTIVAR (0) a un instructor, el sistema consulta `DatosCapacitaciones`.
      - BLOQUEA la operación si el instructor tiene compromisos VIGENTES.
      - Estatus Bloqueantes (IDs):
          * 1 (Programado), 2 (Por Iniciar), 9 (Reprogramado): Compromisos futuros.
          * 3 (En Curso): Compromiso actual.
          * 5 (En Evaluación): Compromiso administrativo pendiente.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Bloqueo Pesimista.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusUsuario`$$

CREATE PROCEDURE `SP_CambiarEstatusUsuario`(
    IN _Id_Admin_Ejecutor    INT,        -- Quién realiza la acción
    IN _Id_Usuario_Objetivo  INT,        -- A quién se desactiva/activa
    IN _Nuevo_Estatus        TINYINT     -- 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* Variables de Estado */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL;
    DECLARE v_Ficha_Objetivo  VARCHAR(50);
    DECLARE v_Estatus_Actual  TINYINT(1);
    DECLARE v_Existe          INT;
    
    /* Variables para el Candado Operativo */
    DECLARE v_Curso_Conflictivo VARCHAR(50); 
    DECLARE v_Estatus_Conflicto VARCHAR(255);

    /* Handler de Errores */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 1: VALIDACIONES PREVIAS
       ======================================================================================== */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Usuario_Objetivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: IDs inválidos.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DATOS [400]: El estatus debe ser 1 o 0.';
    END IF;

    /* Regla Anti-Lockout */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes desactivar tu propia cuenta.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: CANDADO OPERATIVO (INTEGRACIÓN CON TABLA DATOSCAPACITACIONES)
       ======================================================================================== */
    /* Solo validamos si estamos APAGANDO al usuario (0). */
    IF _Nuevo_Estatus = 0 THEN
        
        /* Buscamos si existe ALGÚN curso vivo asignado a este instructor */
        SELECT 
            C.Numero_Capacitacion,
            EC.Nombre
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto
        FROM `DatosCapacitaciones` DC
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            DC.Fk_Id_Instructor = _Id_Usuario_Objetivo
            AND DC.Activo = 1 -- Solo asignaciones vigentes (no borradas)
            
            /* [ACTUALIZACIÓN v2.3]: Se agregan 1 (Programado) y 9 (Reprogramado) */
            AND DC.Fk_Id_CatEstCap IN (1, 2, 3, 5, 9) 
        LIMIT 1;

        /* Si encontramos algo, abortamos con un mensaje muy claro */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar al usuario. Actualmente es Instructor en el curso "', v_Curso_Conflictivo, '" que se encuentra en estatus "', v_Estatus_Conflicto, '". Debe reasignar el curso antes de proceder.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO
       ======================================================================================== */
    START TRANSACTION;

    SELECT 1, `Fk_Id_InfoPersonal`, `Ficha`, `Activo`
    INTO v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo, v_Estatus_Actual
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe.';
    END IF;

    /* Verificación de Idempotencia */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('SIN CAMBIOS: El usuario ya estaba ', IF(_Nuevo_Estatus=1, 'ACTIVO', 'INACTIVO')) AS Mensaje,
               _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: PERSISTENCIA SINCRONIZADA
       ======================================================================================== */
    
    /* 4.1 Desactivar Acceso (Login) */
    UPDATE `Usuarios`
    SET `Activo` = _Nuevo_Estatus,
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 4.2 Desactivar Operatividad (Listas de Selección) */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        UPDATE `Info_Personal`
        SET `Activo` = _Nuevo_Estatus,
            `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
            `updated_at` = NOW()
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN
       ======================================================================================== */
    COMMIT;

    SELECT 
        CONCAT('ÉXITO: Usuario ', v_Ficha_Objetivo, IF(_Nuevo_Estatus=1, ' REACTIVADO', ' DESACTIVADO'), '.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        IF(_Nuevo_Estatus=1, 'ACTIVADO', 'DESACTIVADO') AS Accion;

END$$

DELIMITER ;