DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ActualizarCredencialesPropio`$$

CREATE PROCEDURE `SP_ActualizarCredencialesPropio`(
    IN _Id_Usuario_Sesion  INT,          
    IN _Nuevo_Email        VARCHAR(255), 
    IN _Nueva_Contrasena   VARCHAR(255)  
)
THIS_PROC: BEGIN
    /* Variables de Estado */
    DECLARE v_Email_Act    VARCHAR(255);
    DECLARE v_Pass_Act     VARCHAR(255);
    DECLARE v_Id_Duplicado INT;
    
    /* Variables Normalizadas */
    DECLARE v_Email_Norm   VARCHAR(255);
    DECLARE v_Pass_Norm    VARCHAR(255);

    /* Acumulador de Feedback */
    DECLARE v_Cambios_Detectados VARCHAR(255) DEFAULT '';

    /* Handlers */
    DECLARE EXIT HANDLER FOR 1062 BEGIN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: El correo ya está en uso.'; END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    /* ---------------------------------------------------------
       1. SANITIZACIÓN
       --------------------------------------------------------- */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SEGURIDAD [401]: Sesión no válida.';
    END IF;

    SET v_Email_Norm = NULLIF(TRIM(_Nuevo_Email), '');
    SET v_Pass_Norm  = NULLIF(TRIM(_Nueva_Contrasena), '');

    IF v_Email_Norm IS NULL AND v_Pass_Norm IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debe proporcionar al menos un dato para actualizar.';
    END IF;

    /* ---------------------------------------------------------
       2. VALIDACIÓN DE FORMATO (REGLAS DE NEGOCIO)
       --------------------------------------------------------- */
    
    /* A) Validación de Dominio de Correo (Whitelist) */
    IF v_Email_Norm IS NOT NULL THEN
        IF NOT (v_Email_Norm REGEXP '^[A-Za-z0-9._%+-]+@(pemex\.com|hotmail\.com|gmail\.com|outlook\.es|outlook\.com)$') THEN
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE FORMATO [400]: El correo debe ser institucional (Pemex) o de proveedores autorizados (Gmail, Outlook, Hotmail).';
        END IF;
    END IF;

    /* B) Validación de Complejidad de Contraseña */
    /* Regla: >8 chars, 1 Mayus, 1 Minus, 1 Numero, 1 Especial */
    IF v_Pass_Norm IS NOT NULL THEN
        IF CHAR_LENGTH(v_Pass_Norm) <= 8 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEGURIDAD DÉBIL [400]: La contraseña debe tener más de 8 caracteres.';
        END IF;
        
        /* Nota: Usamos BINARY para que la regex distinga entre Mayúsculas y Minúsculas */
        IF NOT v_Pass_Norm REGEXP BINARY '[A-Z]' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEGURIDAD DÉBIL [400]: La contraseña debe contener al menos una letra MAYÚSCULA.';
        END IF;

        IF NOT v_Pass_Norm REGEXP BINARY '[a-z]' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEGURIDAD DÉBIL [400]: La contraseña debe contener al menos una letra MINÚSCULA.';
        END IF;

        IF NOT v_Pass_Norm REGEXP '[0-9]' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEGURIDAD DÉBIL [400]: La contraseña debe contener al menos un NÚMERO.';
        END IF;

        IF NOT v_Pass_Norm REGEXP '[^a-zA-Z0-9]' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEGURIDAD DÉBIL [400]: La contraseña debe contener al menos un CARÁCTER ESPECIAL (Ej: @, #, $, !).';
        END IF;
    END IF;

    /* ---------------------------------------------------------
       3. LÓGICA TRANSACCIONAL
       --------------------------------------------------------- */
    START TRANSACTION;

    SELECT `Email`, `Contraseña` INTO v_Email_Act, v_Pass_Act
    FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Sesion FOR UPDATE;

    IF v_Email_Act IS NULL THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: Usuario no encontrado.'; END IF;

    -- Detección de cambios Email
    IF v_Email_Norm IS NOT NULL THEN
        IF v_Email_Norm <> v_Email_Act THEN
            SELECT `Id_Usuario` INTO v_Id_Duplicado FROM `Usuarios` WHERE `Email` = v_Email_Norm AND `Id_Usuario` <> _Id_Usuario_Sesion LIMIT 1;
            IF v_Id_Duplicado IS NOT NULL THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El correo ya pertenece a otra cuenta.'; END IF;
            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Correo Electrónico, ');
        ELSE
            SET v_Email_Norm = NULL; 
        END IF;
    END IF;

    -- Detección de cambios Password
    IF v_Pass_Norm IS NOT NULL THEN
        IF v_Pass_Norm <> v_Pass_Act THEN
            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña, ');
        ELSE
            SET v_Pass_Norm = NULL;
        END IF;
    END IF;

    IF v_Cambios_Detectados = '' THEN
        COMMIT;
        SELECT 'No se detectaron cambios.' AS Mensaje, _Id_Usuario_Sesion AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    UPDATE `Usuarios`
    SET 
        `Email` = COALESCE(v_Email_Norm, `Email`),
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    COMMIT;

    SELECT 
        CONCAT('SEGURIDAD ACTUALIZADA: Se modificó: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$
DELIMITER ;