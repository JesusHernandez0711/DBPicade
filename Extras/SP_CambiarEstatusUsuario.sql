/* ============================================================================================
   PROCEDIMIENTO SP_CambiarEstatusUsuario
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHAT")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de "Gestión de Acceso" diseñado para activar (1) o desactivar (0) a un usuario 
   en el sistema. Implementa el patrón de "Baja Lógica" (Soft Delete).

   [PROBLEMA DE ARQUITECTURA]: 
   En el modelo PICADE, la identidad está dividida en dos tablas:
     1. `Usuarios`: Maneja el Login y Acceso.
     2. `Info_Personal`: Maneja la Operatividad (aparecer en listas de instructores, reportes).
   
   Si solo desactivamos `Usuarios`, la persona no puede entrar, pero su nombre sigue apareciendo 
   disponible para asignar cursos en `Info_Personal`. Esto genera inconsistencia.

   [SOLUCIÓN IMPLEMENTADA]: 
   Una transacción atómica que sincroniza el estatus en AMBAS tablas simultáneamente.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE SEGURIDAD (BUSINESS RULES)
   --------------------------------------------------------------------------------------------
   [RN-01] PROTECCIÓN CONTRA AUTO-SABOTAJE (ANTI-LOCKOUT)
      - Regla Crítica: Un Administrador NO puede desactivar su propia cuenta.
      - Justificación: Evita que el sistema quede acéfalo si el último Admin se bloquea por error.

   [RN-02] TRAZABILIDAD CRUZADA
      - Se registra el ID del Admin Ejecutor en los campos de auditoría (`Updated_By`) de 
        ambas tablas afectadas.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Bloqueo Pesimista.
   - BLOQUEO: Se utiliza `FOR UPDATE` para congelar al usuario objetivo y evitar que alguien 
     más lo edite o elimine mientras se procesa el cambio de estatus.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusUsuario`$$

CREATE PROCEDURE `SP_CambiarEstatusUsuario`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,        -- Quién presiona el botón (Auditoría)
    IN _Id_Usuario_Objetivo  INT,        -- A quién se le cambia el estatus (Target)
    IN _Nuevo_Estatus        TINYINT     -- 1 = Activar, 0 = Desactivar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       ======================================================================================== */
    
    /* Punteros de Relación */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL;
    DECLARE v_Ficha_Objetivo  VARCHAR(50);
    
    /* Snapshot de Estado (Para Idempotencia) */
    DECLARE v_Estatus_Actual  TINYINT(1);
    DECLARE v_Existe          INT;

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       ======================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Validación de Integridad de Entrada */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Usuario_Objetivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: IDs de usuario inválidos.';
    END IF;

    /* 2.2 Validación de Dominio (Solo 0 o 1) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DATOS [400]: El estatus debe ser 1 (Activo) o 0 (Inactivo).';
    END IF;

    /* 2.3 Regla Anti-Lockout (Seguridad) */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: Por seguridad, no puedes desactivar tu propia cuenta. Solicita a otro Administrador que lo haga.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: ADQUISICIÓN DE SNAPSHOT
       Buscamos al usuario y bloqueamos su fila. Recuperamos el ID de InfoPersonal para la 
       actualización en cascada. 
       ---------------------------------------------------------------------------------------- */
    SELECT 
        1, 
        `Fk_Id_InfoPersonal`, 
        `Ficha`, 
        `Activo`
    INTO 
        v_Existe, 
        v_Id_InfoPersonal, 
        v_Ficha_Objetivo, 
        v_Estatus_Actual
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* Validación de Existencia */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario objetivo no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: VERIFICACIÓN DE IDEMPOTENCIA
       Si el usuario ya tiene el estatus que pedimos, no hacemos nada.
       ---------------------------------------------------------------------------------------- */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT; -- Liberamos recursos
        
        SELECT 
            CONCAT('SIN CAMBIOS: El usuario ya se encuentra ', IF(_Nuevo_Estatus=1, 'ACTIVO', 'INACTIVO'), '.') AS Mensaje,
            _Id_Usuario_Objetivo AS Id_Usuario,
            'SIN_CAMBIOS' AS Accion;
        
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: PERSISTENCIA SINCRONIZADA (UPDATE CASCADING)
       ======================================================================================== */
    
    /* 4.1 Actualizar Tabla USUARIOS (Capa de Acceso/Login) */
    UPDATE `Usuarios`
    SET 
        `Activo` = _Nuevo_Estatus,
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 4.2 Actualizar Tabla INFO_PERSONAL (Capa Operativa/RRHH) 
       Esto asegura que si el usuario se desactiva, deje de salir en los combos de instructores */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        UPDATE `Info_Personal`
        SET 
            `Activo` = _Nuevo_Estatus,
            `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
            `updated_at` = NOW()
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    COMMIT;

    SELECT 
        CONCAT('ÉXITO: El usuario con Ficha ', v_Ficha_Objetivo, ' ha sido ', IF(_Nuevo_Estatus=1, 'REACTIVADO', 'DESACTIVADO'), ' correctamente.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        IF(_Nuevo_Estatus=1, 'ACTIVADO', 'DESACTIVADO') AS Accion;

END$$

DELIMITER ;

Select * from Cat_Estatus_Capacitacion;