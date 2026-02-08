use Picade;

/* ====================================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_CambiarContrasena]
   ====================================================================================================
   AUTOR: Arquitectura de Software PICADE
   TIPO: Transaccional / Seguridad / Crítico
   
   1. OBJETIVO DE NEGOCIO (THE "WHY")
   ----------------------------------------------------------------------------------------------------
   Módulo exclusivo para la rotación de credenciales de acceso.
   Separa la lógica de "Identidad" (Quién soy) de la lógica de "Acceso" (Cómo entro), cumpliendo con
   el principio de segregación de responsabilidades.

   2. FLUJO DE SEGURIDAD (LARAVEL <-> BD)
   ----------------------------------------------------------------------------------------------------
   Paso 1 (Backend): El usuario envía "Password Actual" y "Password Nuevo".
   Paso 2 (Backend): Laravel usa `Hash::check()` para validar que el "Password Actual" sea correcto.
   Paso 3 (Backend): Laravel genera el Hash del "Password Nuevo" (Bcrypt/Argon2).
   Paso 4 (BD - ESTE SP): Se recibe el ID y el NUEVO HASH para persistirlo en disco.

   3. REGLAS DE BLINDAJE
   ----------------------------------------------------------------------------------------------------
   A) ALCANCE QUIRÚRGICO:
      - Este SP solo toca las columnas `Contraseña`, `updated_at` y `Fk_Usuario_Updated_By`.
      - No permite modificar roles, emails ni datos personales (previniendo elevación de privilegios).

   B) TRAZABILIDAD:
      - Se registra quién hizo el cambio (el propio usuario o un admin) en `Updated_By`.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarContrasena`$$

CREATE PROCEDURE `SP_CambiarContrasena`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Usuario_Target INT,      -- A quién le cambiamos la clave
    IN _Id_Usuario_Actor  INT,      -- Quién está ejecutando el cambio (Mismo usuario o Admin)
    IN _Nuevo_Hash        VARCHAR(255) -- La contraseña YA ENCRIPTADA por Laravel
)
THIS_PROC: BEGIN

    /* Variables de Control */
    DECLARE v_Existe INT DEFAULT 0;

    /* Handlers de Error */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       PASO 1: VALIDACIONES PREVIAS
       ============================================================================================ */
    
    /* 1.1 Integridad de Datos */
    IF _Id_Usuario_Target IS NULL OR _Id_Usuario_Actor IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificadores de usuario inválidos.';
    END IF;

    IF _Nuevo_Hash = '' OR _Nuevo_Hash IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: La nueva contraseña no puede estar vacía.';
    END IF;

    /* 1.2 Existencia del Usuario */
    SELECT COUNT(*) INTO v_Existe FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Target;
    IF v_Existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE REFERENCIA [404]: El usuario especificado no existe.';
    END IF;

    /* ============================================================================================
       PASO 2: ACTUALIZACIÓN ATÓMICA
       ============================================================================================ */
    START TRANSACTION;

    UPDATE `Usuarios`
    SET 
        `Contraseña`            = _Nuevo_Hash,
        `Fk_Usuario_Updated_By` = _Id_Usuario_Actor, -- Auditoría: Quién hizo el cambio
        `updated_at`            = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Target;

    /* ============================================================================================
       PASO 3: CONFIRMACIÓN
       ============================================================================================ */
    COMMIT;

    SELECT 
        'ÉXITO: La contraseña ha sido actualizada correctamente.' AS Mensaje,
        _Id_Usuario_Target AS Id_Usuario,
        'SEGURIDAD_ACTUALIZADA' AS Accion;

END$$

DELIMITER ;