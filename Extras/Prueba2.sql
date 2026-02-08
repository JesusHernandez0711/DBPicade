use Picade;

/* ====================================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_CompletarPerfilPropio]
   ====================================================================================================
   AUTOR: Arquitectura de Software PICADE
   TIPO: Transaccional / Self-Service / Onboarding
   VERSIÓN: 1.1 (Con Validación Total de Catálogos Activos)
   
   1. PROPÓSITO Y OBJETIVO DE NEGOCIO (THE "WHY")
   ----------------------------------------------------------------------------------------------------
   Este procedimiento da soporte al flujo de **"First Login Wizard"** (Asistente de Primer Ingreso).
   
   Cuando un usuario se registra públicamente, sus datos laborales (Puesto, Área, Ubicación) están vacíos.
   Antes de permitirle entrar al Dashboard, el sistema lo obliga a consumir este SP para:
     a) Llenar su Matriz de Adscripción Completa (Puesto, CT, Región, Régimen, Gerencia, Depto).
     b) Corregir posibles errores de captura en su Ficha o Nombre.
   
   2. REGLAS DE BLINDAJE Y SEGURIDAD (SECURITY POSTURE)
   ----------------------------------------------------------------------------------------------------
   A) PRINCIPLE OF LEAST PRIVILEGE (PRIVILEGIO MÍNIMO):
      - Este SP **NO RECIBE** parámetros de `Rol` ni `Estatus`. Mantiene estrictamente
        el Rol que se le asignó al nacer (Participante) y su estatus Activo.
   
   B) AUTO-AUDITORÍA (SELF-AUDIT):
      - Dado que es el propio usuario quien llena sus datos, el campo de trazabilidad
        `Fk_Usuario_Updated_By` se establece automáticamente con su propio `_Id_Usuario_Sesion`.
   
   C) VALIDACIÓN DE VIGENCIA TOTAL (ANTI-ZOMBIE RESOURCES):
      - Defensa: Se valida INDIVIDUALMENTE cada ID de catálogo recibido (Regimen, Puesto, CT, 
        Depto, Región, Gerencia).
      - Lógica: Se consulta si el ID existe Y si `Activo = 1`. Si alguno está inactivo, se rechaza todo.

   D) PROTECCIÓN DE IDENTIDAD (UNIQUE CONSTRAINTS):
      - Validación de unicidad de Ficha/Email con exclusión del propio ID (`Id != Me`).

   3. ESPECIFICACIÓN DE ENTRADA (CONTRACT)
   ----------------------------------------------------------------------------------------------------
   - INPUT: ID del Usuario (Token Auth) + Datos Demográficos + Datos Laborales.
   - NOTA: Todos los catálogos son OBLIGATORIOS en esta fase. No se permite dejar NULLs.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CompletarPerfilPropio`$$

CREATE PROCEDURE `SP_CompletarPerfilPropio`(
    /* -----------------------------------------------------------------
       PARÁMETRO DE IDENTIDAD (AUTH TOKEN CONTEXT)
       ----------------------------------------------------------------- */
    IN _Id_Usuario_Sesion INT,          -- ID del usuario logueado (Viene de Auth::id() en Laravel)

    /* -----------------------------------------------------------------
       BLOQUE 1: DATOS DE CUENTA (CORRECCIONES PERMITIDAS)
       ----------------------------------------------------------------- */
    IN _Ficha            VARCHAR(50),
    IN _Email            VARCHAR(255),

    /* -----------------------------------------------------------------
       BLOQUE 2: DATOS DEMOGRÁFICOS (CORRECCIONES PERMITIDAS)
       ----------------------------------------------------------------- */
    IN _Nombre           VARCHAR(255),
    IN _Apellido_Paterno VARCHAR(255),
    IN _Apellido_Materno VARCHAR(255),
    IN _Fecha_Nacimiento DATE,
    IN _Fecha_Ingreso    DATE,

    /* -----------------------------------------------------------------
       BLOQUE 3: PERFIL LABORAL (LLENADO OBLIGATORIO)
       El usuario DEBE seleccionar todos los parámetros de su ubicación.
       ----------------------------------------------------------------- */
    IN _Id_Regimen       INT,
    IN _Id_Puesto        INT,
    IN _Id_CentroTrabajo INT,
    IN _Id_Departamento  INT,
    IN _Id_Region        INT,
    IN _Id_Gerencia      INT,
    IN _Nivel            VARCHAR(50),
    IN _Clasificacion    VARCHAR(100)
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ESTADO
       ============================================================================================ */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; -- Enlace a la tabla hija.
    DECLARE v_Es_Activo TINYINT(1);             -- Semáforo de vigencia.
    DECLARE v_Id_Duplicado INT;                 -- Para detectar colisiones.
    DECLARE v_MensajeError VARCHAR(255);        -- Mensajes dinámicos.

    /* ============================================================================================
       BLOQUE 1: HANDLERS DE SEGURIDAD
       ============================================================================================ */
    
    /* 1.1 Handler de Colisión (Anti-Race Condition) */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONFLICTO [409]: La Ficha o Email que intentas guardar ya están siendo usados por otro usuario.';
    END;

    /* 1.2 Handler Genérico */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 2: SANITIZACIÓN DE DATOS (DATA HYGIENE)
       ============================================================================================ */
    SET _Ficha            = TRIM(_Ficha);
    SET _Email            = TRIM(_Email);
    SET _Nombre           = TRIM(UPPER(_Nombre));
    SET _Apellido_Paterno = TRIM(UPPER(_Apellido_Paterno));
    SET _Apellido_Materno = TRIM(UPPER(_Apellido_Materno));
    SET _Nivel            = TRIM(UPPER(_Nivel));
    SET _Clasificacion    = TRIM(UPPER(_Clasificacion));

    /* ============================================================================================
       BLOQUE 3: VALIDACIONES PREVIAS (PRE-FLIGHT CHECKS)
       ============================================================================================ */
    
    /* 3.1 Integridad de Sesión */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SESIÓN [401]: No se pudo identificar al usuario.';
    END IF;

    /* 3.2 Integridad Interna (Recuperar enlace Info_Personal) */
    SELECT `Fk_Id_InfoPersonal` INTO v_Id_InfoPersonal FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Sesion;
    
    IF v_Id_InfoPersonal IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Tu usuario no tiene una ficha de información personal vinculada.';
    END IF;

    /* 3.3 Completitud de Perfil (Mandatory Fields) 
       En este flujo, NO permitimos que el usuario deje nada en blanco. */
    IF (_Id_Regimen <= 0 OR _Id_Regimen IS NULL) OR 
       (_Id_Puesto <= 0 OR _Id_Puesto IS NULL) OR 
       (_Id_CentroTrabajo <= 0 OR _Id_CentroTrabajo IS NULL) OR 
       (_Id_Departamento <= 0 OR _Id_Departamento IS NULL) OR 
       (_Id_Region <= 0 OR _Id_Region IS NULL) OR 
       (_Id_Gerencia <= 0 OR _Id_Gerencia IS NULL) THEN
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: Debes completar todos los campos laborales (Régimen, Puesto, Área, Ubicación, Gerencia) para continuar.';
    END IF;

    /* 3.4 Validación de Duplicados Cruzados (Ficha) */
    SELECT `Id_Usuario` INTO v_Id_Duplicado FROM `Usuarios` WHERE `Ficha` = _Ficha AND `Id_Usuario` <> _Id_Usuario_Sesion LIMIT 1;
    IF v_Id_Duplicado IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: La Ficha que ingresaste ya pertenece a otro usuario.';
    END IF;

    /* 3.5 Validación de Duplicados Cruzados (Email) */
    SET v_Id_Duplicado = NULL;
    SELECT `Id_Usuario` INTO v_Id_Duplicado FROM `Usuarios` WHERE `Email` = _Email AND `Id_Usuario` <> _Id_Usuario_Sesion LIMIT 1;
    IF v_Id_Duplicado IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: El Email que ingresaste ya está en uso por otra cuenta.';
    END IF;

    /* ============================================================================================
       BLOQUE 4: VALIDACIÓN DE VIGENCIA DE CATÁLOGOS (ANTI-ZOMBIE RESOURCES)
       Aseguramos que CADA uno de los 6 catálogos seleccionados siga existiendo y estando ACTIVO.
       ============================================================================================ */
    
    /* 4.1 RÉGIMEN */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regimenes_Trabajo` WHERE `Id_CatRegimen` = _Id_Regimen;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: El Régimen de Trabajo seleccionado no está disponible.'; 
    END IF;

    /* 4.2 PUESTO */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Puestos_Trabajo` WHERE `Id_CatPuesto` = _Id_Puesto;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: El Puesto seleccionado no está disponible.'; 
    END IF;

    /* 4.3 CENTRO DE TRABAJO */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Centros_Trabajo` WHERE `Id_CatCT` = _Id_CentroTrabajo;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: El Centro de Trabajo seleccionado no está disponible.'; 
    END IF;

    /* 4.4 DEPARTAMENTO */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Departamentos` WHERE `Id_CatDep` = _Id_Departamento;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: El Departamento seleccionado no está disponible.'; 
    END IF;

    /* 4.5 REGIÓN */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Regiones_Trabajo` WHERE `Id_CatRegion` = _Id_Region;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: La Región seleccionada no está disponible.'; 
    END IF;

    /* 4.6 GERENCIA */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = _Id_Gerencia;
    IF v_Es_Activo = 0 OR v_Es_Activo IS NULL THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VIGENCIA [409]: La Gerencia seleccionada no está disponible.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 5: TRANSACCIÓN DE ACTUALIZACIÓN (ATÓMICA)
       ============================================================================================ */
    START TRANSACTION;

    /* 5.1 Actualizar Info_Personal (Datos Laborales y Humanos) */
    UPDATE `Info_Personal`
    SET 
        `Nombre`            = _Nombre,
        `Apellido_Paterno`  = _Apellido_Paterno,
        `Apellido_Materno`  = _Apellido_Materno,
        `Fecha_Nacimiento`  = _Fecha_Nacimiento,
        `Fecha_Ingreso`     = _Fecha_Ingreso,
        /* Adscripción (Obligatoria y Validada) */
        `Fk_Id_CatRegimen`  = _Id_Regimen,
        `Fk_Id_CatPuesto`   = _Id_Puesto,
        `Fk_Id_CatCT`       = _Id_CentroTrabajo,
        `Fk_Id_CatDep`      = _Id_Departamento,
        `Fk_Id_CatRegion`   = _Id_Region,
        `Fk_Id_CatGeren`    = _Id_Gerencia,
        `Nivel`             = _Nivel,
        `Clasificacion`     = _Clasificacion,
        /* Auto-Auditoría: El usuario se edita a sí mismo */
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion, 
        `updated_at`        = NOW()
    WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;

    /* 5.2 Actualizar Usuarios (Solo Ficha/Email, NUNCA Rol ni Activo) */
    UPDATE `Usuarios`
    SET
        `Ficha`             = _Ficha,
        `Email`             = _Email,
        /* SEGURIDAD: No tocamos Fk_Rol ni Activo. Se mantienen como están. */
        `Fk_Usuario_Updated_By` = _Id_Usuario_Sesion,
        `updated_at`        = NOW()
    WHERE `Id_Usuario` = _Id_Usuario_Sesion;

    /* ============================================================================================
       BLOQUE 6: CONFIRMACIÓN
       ============================================================================================ */
    COMMIT;

    SELECT 
        'ÉXITO: Tu perfil ha sido completado correctamente. Bienvenido al Dashboard.' AS Mensaje,
        _Id_Usuario_Sesion AS Id_Usuario,
        'COMPLETADA' AS Accion;

END$$

DELIMITER ;

/* Agregamos la columna para la URL de la foto 
ALTER TABLE `Usuarios` 
ADD COLUMN `Foto_Perfil_Url` VARCHAR(255) NULL DEFAULT NULL AFTER `Email`;

SELECT * FROM `USUARIOS`;*/