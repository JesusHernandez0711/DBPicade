/* ============================================================================================
   PROCEDIMIENTO: SP_ActualizarCredencialesPropio
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHAT")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor transaccional especializado para la gestión autónoma de credenciales de acceso 
   (Self-Service Security). Permite al usuario modificar sus llaves digitales sin intervención 
   administrativa.

   [ALCANCE OPERATIVO]:
   Gestiona la mutación de los dos vectores de autenticación:
     1. Login (Email): Identificador único de acceso.
     2. Secreto (Contraseña): Hash criptográfico de seguridad.

   [PRE-REQUISITO DE ARQUITECTURA]:
   Este SP asume que la capa de aplicación (Backend/API) YA realizó la validación de la 
   "Contraseña Anterior" antes de invocar este procedimiento. La base de datos confía en que 
   la solicitud es legítima y se limita a persistir los cambios y validar unicidad.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE NEGOCIO (BUSINESS RULES)
   --------------------------------------------------------------------------------------------
   [RN-01] MODIFICACIÓN ATÓMICA Y PARCIAL (FLEXIBILIDAD):
      - El diseño soporta cambios independientes:
         * Solo Email (Password NULL).
         * Solo Password (Email NULL).
         * Ambos simultáneamente.
      - Si un parámetro llega NULL o vacío, se preserva el valor actual en la BD.

   [RN-02] BLINDAJE DE IDENTIDAD (ANTI-COLLISION):
      - Si el usuario intenta cambiar su Email, se verifica estrictamente que el nuevo correo 
        no pertenezca a otro usuario (`Id != Me`).
      - Si hay conflicto, se rechaza la operación con un error 409 controlado.

   [RN-03] IDEMPOTENCIA DE SEGURIDAD (OPTIMIZACIÓN):
      - Si el usuario envía datos idénticos a los actuales (mismo Email, mismo Hash), 
        el sistema detecta la redundancia, reporta éxito ("Sin Cambios") y no toca el disco.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID con Aislamiento de Lectura.
   - BLOQUEO: Pesimista (`FOR UPDATE`) sobre la fila del usuario para evitar condiciones de carrera.
   - TRAZABILIDAD: El usuario se registra a sí mismo como el autor del cambio (`Updated_By`).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ActualizarCredencialesPropio`$$

CREATE PROCEDURE `SP_ActualizarCredencialesPropio`(
    /* Contexto de Sesión */
    IN _Id_Usuario_Sesion  INT,          -- [TOKEN] Quién solicita el cambio

    /* Nuevas Credenciales (Opcionales) */
    IN _Nuevo_Email        VARCHAR(255), -- [LOGIN] NULL si no se quiere cambiar
    IN _Nueva_Contrasena   VARCHAR(255)  -- [HASH] NULL si no se quiere cambiar
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Contenedores para almacenar el estado actual y evaluar cambios.
       ======================================================================================== */
    DECLARE v_Email_Act    VARCHAR(255);
    DECLARE v_Pass_Act     VARCHAR(255);
    DECLARE v_Id_Duplicado INT;
    
    /* Variables Normalizadas */
    DECLARE v_Email_Norm   VARCHAR(255);
    DECLARE v_Pass_Norm    VARCHAR(255);

    /* Acumulador de Feedback */
    DECLARE v_Cambios_Detectados VARCHAR(255) DEFAULT '';

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MECANISMOS DE DEFENSA)
       ======================================================================================== */
    
    /* [1.1] Handler para colisión de Email (Unique Key)
       Objetivo: Capturar si otro usuario registró el mismo correo en el último milisegundo. */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: El correo electrónico ingresado ya está siendo usado por otro usuario.';
    END;

    /* [1.2] Handler Genérico (Crash Safety) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN (INPUT HYGIENE)
       ======================================================================================== */
    
    /* 2.1 Integridad de Sesión */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SEGURIDAD [401]: Sesión no válida.';
    END IF;

    /* 2.2 Normalización de Inputs
       Convertimos cadenas vacías o espacios en NULL para que la lógica COALESCE funcione. */
    SET v_Email_Norm = NULLIF(TRIM(_Nuevo_Email), '');
    SET v_Pass_Norm  = NULLIF(TRIM(_Nueva_Contrasena), '');

    /* 2.3 Validación de Propósito
       Evitamos transacciones vacías. Al menos un dato debe venir para actualizar. */
    IF v_Email_Norm IS NULL AND v_Pass_Norm IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debe proporcionar al menos un dato para actualizar (Email o Contraseña).';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       ======================================================================================== */
    START TRANSACTION;

    /* Bloqueo de Fila: Nadie puede modificar esta cuenta mientras cambiamos las llaves.
       Solo leemos las columnas necesarias para comparar. */
    SELECT `Email`, `Contraseña`
    INTO v_Email_Act, v_Pass_Act
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Sesion
    FOR UPDATE;

    /* Safety Check: Si el usuario fue borrado justo antes de entrar aquí */
    IF v_Email_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La cuenta de usuario no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: DETECCIÓN DE CAMBIOS Y VALIDACIÓN DE UNICIDAD
       ======================================================================================== */

    /* 4.1 Análisis de Email */
    IF v_Email_Norm IS NOT NULL THEN
        IF v_Email_Norm <> v_Email_Act THEN
            /* Cambio detectado: Verificamos disponibilidad */
            SELECT `Id_Usuario` INTO v_Id_Duplicado 
            FROM `Usuarios` 
            WHERE `Email` = v_Email_Norm AND `Id_Usuario` <> _Id_Usuario_Sesion 
            LIMIT 1;

            IF v_Id_Duplicado IS NOT NULL THEN
                ROLLBACK;
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El nuevo correo electrónico ya pertenece a otra cuenta.';
            END IF;

            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Correo Electrónico, ');
        ELSE
            /* Falso Positivo: El usuario envió el mismo correo que ya tiene. Lo anulamos. */
            SET v_Email_Norm = NULL; 
        END IF;
    END IF;

    /* 4.2 Análisis de Contraseña */
    IF v_Pass_Norm IS NOT NULL THEN
        /* Comparamos el hash nuevo contra el actual. */
        IF v_Pass_Norm <> v_Pass_Act THEN
            SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña, ');
        ELSE
            SET v_Pass_Norm = NULL;
        END IF;
    END IF;

    /* ========================================================================================
       BLOQUE 5: VERIFICACIÓN DE IDEMPOTENCIA
       Si no hubo cambios reales, salimos sin tocar disco.
       ======================================================================================== */
    IF v_Cambios_Detectados = '' THEN
        COMMIT;
        SELECT 'No se detectaron cambios en las credenciales.' AS Mensaje, _Id_Usuario_Sesion AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 6: PERSISTENCIA (UPDATE)
       ======================================================================================== */
    
    UPDATE `Usuarios`
    SET 
        /* Si v_Email_Norm es NULL (porque no cambió o no se envió), COALESCE mantiene el actual */
        `Email` = COALESCE(v_Email_Norm, `Email`),
        
        /* Si v_Pass_Norm es NULL, COALESCE mantiene la actual */
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),

        /* Auditoría: El usuario modificó su propia seguridad */
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    /* ========================================================================================
       BLOQUE 7: RESPUESTA DINÁMICA
       ======================================================================================== */
    COMMIT;

    /* Ejemplo Salida: "SEGURIDAD ACTUALIZADA: Se modificó: Correo Electrónico, Contraseña." */
    SELECT 
        CONCAT('SEGURIDAD ACTUALIZADA: Se modificó: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;