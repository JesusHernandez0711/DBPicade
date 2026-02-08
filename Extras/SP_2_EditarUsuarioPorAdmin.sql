/* ============================================================================================
   PROCEDIMIENTO: SP_EditarUsuarioPorAdmin
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. PROPÓSITO Y ALCANCE (THE "WHAT")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de "Edición Maestro" utilizado por los Administradores para corregir o 
   actualizar el expediente completo de cualquier usuario.

   [PODERES DEL ADMINISTRADOR EN ESTE SP]:
   1. Corrección de Identidad: Puede cambiar Ficha, Email y Foto.
   2. Reset de Seguridad: Puede establecer una nueva Contraseña (hash) directamente, 
      sin necesidad de validación de la anterior (útil para "Olvidé mi contraseña").
   3. Reasignación Laboral: Puede cambiar Puesto, Área y Ubicación libremente.
   4. Escalado de Privilegios: Puede cambiar el ROL del usuario.

   [EXCLUSIÓN IMPORTANTE]:
   - El Estatus (Activo/Inactivo) NO se toca aquí. Se gestiona en un SP atómico separado 
     para evitar desactivaciones accidentales durante una edición de rutina.

   --------------------------------------------------------------------------------------------
   II. REGLAS DE NEGOCIO (BUSINESS RULES)
   --------------------------------------------------------------------------------------------
   [RN-01] RESET DE CONTRASEÑA CONDICIONAL
      - Si el Admin envía `_Nueva_Contrasena` con valor: Se actualiza el hash.
      - Si el Admin envía `NULL` o vacío: Se conserva la contraseña actual del usuario.

   [RN-02] TRAZABILIDAD JERÁRQUICA
      - El campo `Fk_Usuario_Updated_By` registra el ID del ADMINISTRADOR que ejecutó la acción,
        permitiendo auditar "quién cambió los datos de quién".

   [RN-03] IDEMPOTENCIA Y CONCURRENCIA
      - Mantiene el motor de detección de cambios ("Sin Cambios" = No Update).
      - Mantiene el Bloqueo Pesimista (`FOR UPDATE`) para evitar condiciones de carrera.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID.
   - VALIDACIÓN: Delegada al Framework (Longitud) + Híbrida en BD (Existencia de Catálogos).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_EditarUsuarioPorAdmin`(
    /* -----------------------------------------------------------------
       1. CONTEXTO DE AUDITORÍA (ACTORES)
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,   -- Quién realiza el cambio
    IN _Id_Usuario_Objetivo  INT,   -- A quién se le aplica el cambio

    /* -----------------------------------------------------------------
       2. SEGURIDAD Y ACCESO (CRÍTICOS)
       ----------------------------------------------------------------- */
    IN _Ficha                VARCHAR(50),
    IN _Email                VARCHAR(255),
    IN _Id_Rol               INT,          -- Admin puede cambiar el Rol
    IN _Nueva_Contrasena     VARCHAR(255), -- OPCIONAL: Si viene lleno, se resetea el password
    IN _Url_Foto             VARCHAR(255),

    /* -----------------------------------------------------------------
       3. IDENTIDAD HUMANA
       ----------------------------------------------------------------- */
    IN _Nombre               VARCHAR(255),
    IN _Apellido_Paterno     VARCHAR(255),
    IN _Apellido_Materno     VARCHAR(255),
    IN _Fecha_Nacimiento     DATE,
    IN _Fecha_Ingreso        DATE,

    /* -----------------------------------------------------------------
       4. MATRIZ DE ADSCRIPCIÓN
       ----------------------------------------------------------------- */
    IN _Id_Regimen           INT, 
    IN _Id_Puesto            INT, 
    IN _Id_CentroTrabajo     INT, 
    IN _Id_Departamento      INT, 
    IN _Id_Region            INT, 
    IN _Id_Gerencia          INT, 
    
    /* -----------------------------------------------------------------
       5. METADATOS
       ----------------------------------------------------------------- */
    IN _Nivel                VARCHAR(50),
    IN _Clasificacion        VARCHAR(100)
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ESTADO
       ============================================================================================ */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; 
    DECLARE v_Es_Activo       TINYINT(1);       
    DECLARE v_Id_Duplicado    INT;              
    
    /* Normalización de IDs */
    DECLARE v_Id_Puesto_Norm   INT;
    DECLARE v_Id_CT_Norm       INT;
    DECLARE v_Id_Dep_Norm      INT;
    DECLARE v_Id_Gerencia_Norm INT;
    DECLARE v_Pass_Norm        VARCHAR(255); -- Para manejar el password opcional

    /* Snapshots (Estado Actual en BD) */
    DECLARE v_Ficha_Act       VARCHAR(50);
    DECLARE v_Email_Act       VARCHAR(255); 
    DECLARE v_Rol_Act         INT;
    DECLARE v_Foto_Act        VARCHAR(255);
    
    DECLARE v_Nombre_Act      VARCHAR(255);
    DECLARE v_Paterno_Act     VARCHAR(255);
    DECLARE v_Materno_Act     VARCHAR(255);
    DECLARE v_Nacim_Act       DATE;
    DECLARE v_Ingre_Act       DATE;
    
    DECLARE v_Regimen_Act     INT;
    DECLARE v_Puesto_Act      INT;
    DECLARE v_CT_Act          INT;
    DECLARE v_Dep_Act         INT;
    DECLARE v_Region_Act      INT;
    DECLARE v_Geren_Act       INT;
    DECLARE v_Nivel_Act       VARCHAR(50);
    DECLARE v_Clasif_Act      VARCHAR(100);

    /* Acumulador de Cambios */
    DECLARE v_Cambios_Detectados VARCHAR(1000) DEFAULT '';

    /* ============================================================================================
       BLOQUE 1: HANDLERS DE SEGURIDAD
       ============================================================================================ */
    
    /* [1.1] Colisión de Unicidad (Ficha/Email duplicados) */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha o el Email ingresados ya pertenecen a otro usuario.';
    END;

    /* [1.2] Integridad Referencial Rota (Catálogo borrado) */
    DECLARE EXIT HANDLER FOR 1452
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: Uno de los catálogos seleccionados dejó de existir en el sistema.';
    END;

    /* [1.3] Handler Genérico */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN Y NORMALIZACIÓN
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    SET _Url_Foto         = NULLIF(TRIM(_Url_Foto), '');
    /* Password: Si viene vacío o null, lo dejamos NULL para indicar "No Cambiar" */
    SET v_Pass_Norm       = NULLIF(TRIM(_Nueva_Contrasena), '');

    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* Normalización de IDs (0 -> NULL) */
    SET v_Id_Puesto_Norm   = NULLIF(_Id_Puesto, 0);
    SET v_Id_CT_Norm       = NULLIF(_Id_CentroTrabajo, 0);
    SET v_Id_Dep_Norm      = NULLIF(_Id_Departamento, 0);
    SET v_Id_Gerencia_Norm = NULLIF(_Id_Gerencia, 0);

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (FAIL FAST)
       ============================================================================================ */
    
    /* 3.1 Integridad de Actores */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Admin_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [403]: ID de Administrador no válido.';
    END IF;

    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Usuario Objetivo no válido.';
    END IF;

    /* 3.2 Campos Obligatorios de Sistema */
    IF _Id_Rol <= 0 OR _Id_Rol IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El ROL es obligatorio.';
    END IF;

    /* 3.3 Regla de Adscripción Híbrida */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Régimen y Región son obligatorios.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: INICIO TRANSACCIÓN Y BLOQUEO PESIMISTA
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 Bloqueo del USUARIO OBJETIVO
       Usamos `FOR UPDATE` para asegurar que nadie más lo edite simultáneamente. */
    SELECT 
        `Fk_Id_InfoPersonal`, `Ficha`, `Email`, `Foto_Perfil_Url`, `Fk_Rol`
    INTO 
        v_Id_InfoPersonal, v_Ficha_Act, v_Email_Act, v_Foto_Act, v_Rol_Act
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    IF v_Id_InfoPersonal IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario objetivo no existe.';
    END IF;

    /* 4.2 Bloqueo de INFO_PERSONAL */
    SELECT 
        `Nombre`, `Apellido_Paterno`, `Apellido_Materno`, `Fecha_Nacimiento`, `Fecha_Ingreso`,
        `Fk_Id_CatRegimen`, `Fk_Id_CatPuesto`, `Fk_Id_CatCT`, `Fk_Id_CatDep`, `Fk_Id_CatRegion`, `Fk_Id_CatGeren`,
        `Nivel`, `Clasificacion`
    INTO 
        v_Nombre_Act, v_Paterno_Act, v_Materno_Act, v_Nacim_Act, v_Ingre_Act,
        v_Regimen_Act, v_Puesto_Act, v_CT_Act, v_Dep_Act, v_Region_Act, v_Geren_Act,
        v_Nivel_Act, v_Clasif_Act
    FROM `Info_Personal`
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal
    FOR UPDATE;

    /* ============================================================================================
       BLOQUE 5: MOTOR DE DETECCIÓN DE CAMBIOS
       Compara Snapshot vs Inputs.
       ============================================================================================ */
    
    /* 5.1 Credenciales y Seguridad */
    IF NOT (v_Ficha_Act <=> _Ficha) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Ficha, '); END IF;
    IF NOT (v_Email_Act <=> _Email) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Email, '); END IF;
    IF NOT (v_Rol_Act <=> _Id_Rol)  THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Rol, '); END IF;
    IF NOT (v_Foto_Act <=> _Url_Foto) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Foto, '); END IF;
    
    /* ** Detección especial de Contraseña ** */
    /* Si v_Pass_Norm tiene valor, significa que el Admin quiere resetearla. Eso es un cambio. */
    IF v_Pass_Norm IS NOT NULL THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Contraseña (Reset), ');
    END IF;

    /* 5.2 Datos Personales */
    IF NOT (v_Nombre_Act <=> _Nombre) OR NOT (v_Paterno_Act <=> _Apellido_Paterno) OR 
       NOT (v_Materno_Act <=> _Apellido_Materno) OR NOT (v_Nacim_Act <=> _Fecha_Nacimiento) THEN
        SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Datos Personales, ');
    END IF;

    IF NOT (v_Ingre_Act <=> _Fecha_Ingreso) THEN SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Fecha Ingreso, '); END IF;

    /* 5.3 Datos Laborales */
    IF NOT (v_Regimen_Act <=> _Id_Regimen) OR NOT (v_Region_Act <=> _Id_Region) OR
       NOT (v_Puesto_Act <=> v_Id_Puesto_Norm) OR NOT (v_CT_Act <=> v_Id_CT_Norm) OR
       NOT (v_Dep_Act <=> v_Id_Dep_Norm) OR NOT (v_Geren_Act <=> v_Id_Gerencia_Norm) OR
       NOT (v_Nivel_Act <=> _Nivel) OR NOT (v_Clasif_Act <=> _Clasificacion) THEN
       
       SET v_Cambios_Detectados = CONCAT(v_Cambios_Detectados, 'Adscripción Laboral, ');
    END IF;

    /* ============================================================================================
       BLOQUE 6: VERIFICACIÓN DE IDEMPOTENCIA
       Si no hay cambios, retornamos éxito sin tocar disco.
       ============================================================================================ */
    IF v_Cambios_Detectados = '' THEN
        COMMIT; 
        SELECT 'No se detectaron cambios en el expediente.' AS Mensaje, _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 7: VALIDACIONES DE NEGOCIO (POST-LOCK)
       ============================================================================================ */

    /* 7.1 Colisión de Ficha (Excluyendo al usuario objetivo) */
    IF LOCATE('Ficha', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha asignada ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.2 Colisión de Email (Excluyendo al usuario objetivo) */
    IF LOCATE('Email', v_Cambios_Detectados) > 0 THEN
        SELECT `Id_Usuario` INTO v_Id_Duplicado 
        FROM `Usuarios` WHERE `Email` = _Email AND `Id_Usuario` <> _Id_Usuario_Objetivo LIMIT 1;
        
        IF v_Id_Duplicado IS NOT NULL THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El Email asignado ya pertenece a otro usuario.';
        END IF;
    END IF;

    /* 7.3 Vigencia de Catálogos (Validación Manual para Feedback) */
    /* Catálogos Críticos (Sistema) */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Roles` WHERE `Id_Rol` = _Id_Rol;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: El Rol seleccionado no existe o está inactivo.'; END IF;

    /* Catálogos Laborales */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Régimen no válido.'; END IF;

    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Región no válida.'; END IF;

    /* Opcionales (Solo si traen datos) */
    IF v_Id_Puesto_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = v_Id_Puesto_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Puesto inactivo.'; END IF;
    END IF;

    IF v_Id_CT_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = v_Id_CT_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Centro de Trabajo inactivo.'; END IF;
    END IF;

    IF v_Id_Dep_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = v_Id_Dep_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Departamento inactivo.'; END IF;
    END IF;

    IF v_Id_Gerencia_Norm IS NOT NULL THEN
        SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = v_Id_Gerencia_Norm;
        IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN ROLLBACK; SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA: Gerencia inactiva.'; END IF;
    END IF;

    /* ============================================================================================
       BLOQUE 8: PERSISTENCIA (UPDATE)
       ============================================================================================ */
    
    /* 8.1 Actualizar Info Personal (Datos Humanos) */
    UPDATE `Info_Personal`
    SET 
        `Nombre` = _Nombre, `Apellido_Paterno` = _Apellido_Paterno, `Apellido_Materno` = _Apellido_Materno,
        `Fecha_Nacimiento` = _Fecha_Nacimiento, `Fecha_Ingreso` = _Fecha_Ingreso,
        `Fk_Id_CatRegimen` = _Id_Regimen, `Fk_Id_CatPuesto` = v_Id_Puesto_Norm,
        `Fk_Id_CatCT` = v_Id_CT_Norm, `Fk_Id_CatDep` = v_Id_Dep_Norm,
        `Fk_Id_CatRegion` = _Id_Region, `Fk_Id_CatGeren` = v_Id_Gerencia_Norm,
        `Nivel` = _Nivel, `Clasificacion` = _Clasificacion,
        /* Auditoría Cruzada: Quien modifica es el Admin */
        `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 8.2 Actualizar Usuario (Credenciales y Seguridad) */
    UPDATE `Usuarios`
    SET
        `Ficha` = _Ficha,
        `Email` = _Email,           -- Admin SÍ puede corregir email
        `Foto_Perfil_Url` = _Url_Foto,
        `Fk_Rol` = _Id_Rol,         -- Admin SÍ puede cambiar roles
        
        /* Contraseña: Usamos COALESCE. Si v_Pass_Norm es NULL, se queda la misma. */
        `Contraseña` = COALESCE(v_Pass_Norm, `Contraseña`),
        
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor,
        `updated_at` = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* ============================================================================================
       BLOQUE 9: CONFIRMACIÓN Y RESPUESTA
       ============================================================================================ */
    COMMIT;

    /* Feedback: "ÉXITO: Se ha actualizado: Rol, Contraseña (Reset), Email." */
    SELECT 
        CONCAT('ÉXITO: Se ha actualizado: ', TRIM(TRAILING ', ' FROM v_Cambios_Detectados), '.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        'ACTUALIZADA' AS Accion;

END$$

DELIMITER ;