use Picade;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTOS DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */
/* ======================================================================================
   VIEW: Vista_Direcciones
   ======================================================================================
   OBJETIVO
   --------
   Exponer una vista "plana" con la jerarquía completa:
      Municipio -> Estado -> País
   para usarse en:
      - buscadores globales
      - tablas/listados
      - pantallas de administración
   NOTA
   ----
   - La vista NO filtra Activo; ese filtro se hace en los SPs.
   - El campo "Estatus" representa Municipio.Activo (borrado lógico).
====================================================================================== */

-- DROP VIEW IF EXISTS Picade.Vista_Direcciones;

CREATE OR REPLACE
    ALGORITHM = UNDEFINED 
    DEFINER = `root`@`localhost` 
    SQL SECURITY DEFINER
VIEW `Picade`.`Vista_Direcciones` AS
    SELECT 
        `Mun`.`Id_Municipio` AS `Id_Municipio`,
        `Mun`.`Codigo` AS `Codigo_Municipio`,
        `Mun`.`Nombre` AS `Nombre_Municipio`,
        `Est`.`Codigo` AS `Codigo_Estado`,
        `Est`.`Nombre` AS `Nombre_Estado`,
        `Pais`.`Codigo` AS `Codigo_Pais`,
        `Pais`.`Nombre` AS `Nombre_Pais`,
        `Mun`.`Activo` AS `Estatus`
    FROM
        ((`Picade`.`Municipio` `Mun`
        JOIN `Picade`.`Estado` `Est` ON (`Mun`.`Fk_Id_Estado` = `Est`.`Id_Estado`))
        JOIN `Picade`.`Pais` `Pais` ON (`Est`.`Fk_Id_Pais` = `Pais`.`Id_Pais`));

/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarUbicaciones
   ============================================================================================
   OBJETIVO
   --------
   Resolver o registrar una jerarquía completa de ubicaciones:
      País -> Estado -> Municipio
   en una sola operación, pensada para FORMULARIO donde TODO es obligatorio
   (Código y Nombre en los 3 niveles).

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   Para cada nivel (País, Estado, Municipio) este SP aplica la MISMA regla:

   1) Busca primero por CÓDIGO (regla principal) dentro de su “padre” cuando aplica.
      - Si existe: valida que el NOMBRE coincida.
      - Si no coincide: ERROR controlado (conflicto Código <-> Nombre).

   2) Si no existe por CÓDIGO, busca por NOMBRE dentro de su “padre” cuando aplica.
      - Si existe: valida que el CÓDIGO coincida.
      - Si no coincide: ERROR controlado (conflicto Nombre <-> Código).

   3) Si NO existe por CÓDIGO ni por NOMBRE:
      - Crea el registro (INSERT).

   4) Si existe y está Activo = 0:
      - Reactiva (UPDATE Activo=1).

   ACCIONES DEVUELTAS
   ------------------
   El SP devuelve una acción por nivel:
      Accion_Pais      = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Estado    = 'CREADA' | 'REUSADA' | 'REACTIVADA'
      Accion_Municipio = 'CREADA' | 'REUSADA' | 'REACTIVADA'

   - 'CREADA'      => se insertó un nuevo registro.
   - 'REUSADA'     => ya existía activa y se reutilizó (no se insertó).
   - 'REACTIVADA'  => ya existía pero estaba inactiva, se reactivó y se reutilizó.

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - Usa TRANSACTION: si algo falla, ROLLBACK y RESIGNAL (no quedan datos a medias).
   - Resolución determinística (nada de "OR ... LIMIT 1").
   - Blindaje ante concurrencia/doble-submit:
       * Los SELECT de búsqueda usan FOR UPDATE para serializar la lectura cuando hay fila.
       * Las constraints UNIQUE (Código+FK, Nombre+FK) son el candado final contra duplicados.

   RESULTADO
   ---------
   Retorna:
   - Id_Pais, Id_Estado, Id_Municipio
   - Accion_* por cada nivel
   - Id_Nuevo_Pais       SOLO si Accion_Pais='CREADA', si no NULL
   - Id_Nuevo_Estado     SOLO si Accion_Estado='CREADA', si no NULL
   - Id_Nuevo_Municipio  SOLO si Accion_Municipio='CREADA', si no NULL
============================================================================================ */

DELIMITER $$

/* -- DROP PROCEDURE IF EXISTS SP_RegistrarUbicaciones$$ */
CREATE PROCEDURE SP_RegistrarUbicaciones(
    IN _Codigo_Municipio VARCHAR(50),   /* Código del Municipio (OBLIGATORIO en formulario) */
    IN _Nombre_Municipio VARCHAR(255),  /* Nombre del Municipio (OBLIGATORIO) */
    IN _Codigo_Estado    VARCHAR(50),   /* Código del Estado (OBLIGATORIO) */
    IN _Nombre_Estado    VARCHAR(255),  /* Nombre del Estado (OBLIGATORIO) */
    IN _Codigo_Pais      VARCHAR(50),   /* Código del País (OBLIGATORIO) */
    IN _Nombre_Pais      VARCHAR(255)   /* Nombre del País (OBLIGATORIO) */
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
       ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Pais      INT DEFAULT NULL;
    DECLARE v_Id_Estado    INT DEFAULT NULL;
    DECLARE v_Id_Municipio INT DEFAULT NULL;

    /* Buffers para validación cruzada cuando el registro ya existe */
    DECLARE v_Codigo VARCHAR(50);
    DECLARE v_Nombre VARCHAR(255);
    DECLARE v_Activo TINYINT(1);

    /* Acciones por nivel */
    DECLARE v_Accion_Pais      VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Estado    VARCHAR(20) DEFAULT NULL;
    DECLARE v_Accion_Municipio VARCHAR(20) DEFAULT NULL;

    /* ----------------------------------------------------------------------------------------
       MANEJO DE ERRORES
    ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Registro Duplicado por concurrencia o restricción UNIQUE. Refresca y reintenta; si ya existe se reutilizará/reactivará.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN BÁSICA
    ---------------------------------------------------------------------------------------- */
    SET _Codigo_Pais      = NULLIF(TRIM(_Codigo_Pais), '');
    SET _Nombre_Pais      = NULLIF(TRIM(_Nombre_Pais), '');
    SET _Codigo_Estado    = NULLIF(TRIM(_Codigo_Estado), '');
    SET _Nombre_Estado    = NULLIF(TRIM(_Nombre_Estado), '');
    SET _Codigo_Municipio = NULLIF(TRIM(_Codigo_Municipio), '');
    SET _Nombre_Municipio = NULLIF(TRIM(_Nombre_Municipio), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES DE NEGOCIO (FORMULARIO: TODO OBLIGATORIO)
    ---------------------------------------------------------------------------------------- */
    IF _Codigo_Pais IS NULL OR _Nombre_Pais IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: País incompleto (Código y Nombre obligatorios).';
    END IF;

    IF _Codigo_Estado IS NULL OR _Nombre_Estado IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Estado incompleto (Código y Nombre obligatorios).';
    END IF;

    IF _Codigo_Municipio IS NULL OR _Nombre_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Municipio incompleto (Código y Nombre obligatorios).';
    END IF;

    /* ----------------------------------------------------------------------------------------
       INICIO TRANSACCIÓN
    ---------------------------------------------------------------------------------------- */
    START TRANSACTION;

    /* ========================================================================================
       1) RESOLVER / CREAR PAÍS
       ======================================================================================== */

    /* 1A) Buscar por CÓDIGO */
    SET v_Id_Pais = NULL;
    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Codigo = _Codigo_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Pais THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Código existe pero el Nombre no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;
            SET v_Accion_Pais = 'REACTIVADA';
        ELSE
            SET v_Accion_Pais = 'REUSADA';
        END IF;

    ELSE
        /* 1B) Buscar por NOMBRE */
        SELECT Id_Pais, Codigo, Nombre, Activo
          INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
        FROM Pais
        WHERE Nombre = _Nombre_Pais
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Pais IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Pais THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Nombre existe pero el Código no coincide.';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Pais
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Pais = v_Id_Pais;
                SET v_Accion_Pais = 'REACTIVADA';
            ELSE
                SET v_Accion_Pais = 'REUSADA';
            END IF;

        ELSE
            /* 1C) Crear */
            INSERT INTO Pais (Codigo, Nombre, Activo)
            VALUES (_Codigo_Pais, _Nombre_Pais, 1);

            SET v_Id_Pais = LAST_INSERT_ID();
            SET v_Accion_Pais = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       2) RESOLVER / CREAR ESTADO (dentro del País resuelto)
       ======================================================================================== */

    /* 2A) Buscar por CÓDIGO dentro del país */
    SET v_Id_Estado = NULL;
    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Codigo = _Codigo_Estado
      AND Fk_Id_Pais = v_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Estado THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Código existe pero el Nombre no coincide (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;
            SET v_Accion_Estado = 'REACTIVADA';
        ELSE
            SET v_Accion_Estado = 'REUSADA';
        END IF;

    ELSE
        /* 2B) Buscar por NOMBRE dentro del país */
        SELECT Id_Estado, Codigo, Nombre, Activo
          INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
        FROM Estado
        WHERE Nombre = _Nombre_Estado
          AND Fk_Id_Pais = v_Id_Pais
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Estado IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Estado THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Nombre existe pero el Código no coincide (en ese País).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Estado
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Estado = v_Id_Estado;
                SET v_Accion_Estado = 'REACTIVADA';
            ELSE
                SET v_Accion_Estado = 'REUSADA';
            END IF;

        ELSE
            /* 2C) Crear */
            INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais, Activo)
            VALUES (_Codigo_Estado, _Nombre_Estado, v_Id_Pais, 1);

            SET v_Id_Estado = LAST_INSERT_ID();
            SET v_Accion_Estado = 'CREADA';
        END IF;
    END IF;

    /* ========================================================================================
       3) RESOLVER / CREAR MUNICIPIO (dentro del Estado resuelto)
       ======================================================================================== */

    /* 3A) Buscar por CÓDIGO dentro del estado */
    SET v_Id_Municipio = NULL;
    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Codigo = _Codigo_Municipio
      AND Fk_Id_Estado = v_Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Nombre <> _Nombre_Municipio THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Código existe pero el Nombre no coincide (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;
            SET v_Accion_Municipio = 'REACTIVADA';
        ELSE
            SET v_Accion_Municipio = 'REUSADA';
        END IF;

    ELSE
        /* 3B) Buscar por NOMBRE dentro del estado */
        SELECT Id_Municipio, Codigo, Nombre, Activo
          INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
        FROM Municipio
        WHERE Nombre = _Nombre_Municipio
          AND Fk_Id_Estado = v_Id_Estado
        LIMIT 1
        FOR UPDATE;

        IF v_Id_Municipio IS NOT NULL THEN
            IF v_Codigo <> _Codigo_Municipio THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Nombre existe pero el Código no coincide (en ese Estado).';
            END IF;

            IF v_Activo = 0 THEN
                UPDATE Municipio
                SET Activo = 1, updated_at = NOW()
                WHERE Id_Municipio = v_Id_Municipio;
                SET v_Accion_Municipio = 'REACTIVADA';
            ELSE
                SET v_Accion_Municipio = 'REUSADA';
            END IF;

        ELSE
            /* 3C) Crear */
            INSERT INTO Municipio (Codigo, Nombre, Fk_Id_Estado, Activo)
            VALUES (_Codigo_Municipio, _Nombre_Municipio, v_Id_Estado, 1);

            SET v_Id_Municipio = LAST_INSERT_ID();
            SET v_Accion_Municipio = 'CREADA';
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       CONFIRMAR TRANSACCIÓN Y RESPUESTA
    ---------------------------------------------------------------------------------------- */
    COMMIT;

    SELECT
        'Registro Exitoso' AS Mensaje,

        v_Id_Pais      AS Id_Pais,
        v_Id_Estado    AS Id_Estado,
        v_Id_Municipio AS Id_Municipio,

        v_Accion_Pais      AS Accion_Pais,
        v_Accion_Estado    AS Accion_Estado,
        v_Accion_Municipio AS Accion_Municipio,

        CASE 
			WHEN v_Accion_Pais = 'CREADA' THEN v_Id_Pais 
			ELSE NULL 
		END AS Id_Nuevo_Pais,
        CASE 
			WHEN v_Accion_Estado = 'CREADA' THEN v_Id_Estado 
            ELSE NULL 
		END AS Id_Nuevo_Estado,
        CASE 
			WHEN v_Accion_Municipio = 'CREADA' THEN v_Id_Municipio 
            ELSE NULL 
		END AS Id_Nuevo_Municipio;

END$$

DELIMITER ;

/* ============================================================================================
	PROCEDIMIENTO: SP_ConsultarPaisEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar País" o un modal de detalle.

   ¿QUÉ RESUELVE?
   --------------
   Devuelve el registro del País por Id, incluyendo su estatus (Activo/Inactivo),
   para que el frontend pueda:
   - Precargar inputs (Código / Nombre)
   - Mostrar el estatus actual
   - Decidir si habilita acciones (reactivar / desactivar)

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 aquí, porque para edición/admin necesitas poder
     consultar también países inactivos.
   - Validamos Id y existencia para devolver errores controlados (no “null” silencioso).
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarPaisEspecifico$$
CREATE PROCEDURE SP_ConsultarPaisEspecifico(
    IN _Id_Pais INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       - Evita llamadas con NULL, 0, negativos, etc.
    ------------------------------------------------------------ */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El país existe
       - Si no existe, no tiene sentido cargar el formulario
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae el país exacto
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Id_Pais,
        Codigo,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarEstadoEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Estado".

   ¿QUÉ RESUELVE?
   --------------
   Para editar un Estado, el frontend normalmente necesita:
   - Datos del Estado (Código, Nombre, Activo)
   - El País al que pertenece (para preseleccionar el -- DROPdown de País)
   - (Opcional UI) Mostrar datos del País (Código/Nombre) como referencia

   NOTA DE DISEÑO
   --------------
   - NO filtramos por Activo=1 porque un admin puede necesitar editar/ver un estado inactivo.
   - Validamos Id y existencia para que el backend falle con un mensaje claro.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarEstadoEspecifico$$
CREATE PROCEDURE SP_ConsultarEstadoEspecifico(
    IN _Id_Estado INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
    ------------------------------------------------------------ */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El estado existe
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Estado + País padre
       - Esto permite precargar el -- DROPdown de País en el frontend
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Est.Id_Estado,
        Est.Codigo      AS Codigo_Estado,
        Est.Nombre      AS Nombre_Estado,
        
        Est.Fk_Id_Pais  AS Id_Pais,
        Pais.Codigo     AS Codigo_Pais,
        Pais.Nombre     AS Nombre_Pais,
		
        Est.Activo      AS Activo_Estado,
        Est.created_at  AS created_at_estado,
        Est.updated_at  AS updated_at_estado
    FROM Estado Est
    JOIN Pais  Pais ON Pais.Id_Pais = Est.Fk_Id_Pais
    WHERE Est.Id_Estado = _Id_Estado
    LIMIT 1;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarMunicipioEspecifico
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario abre la pantalla "Editar Municipio".

   ¿QUÉ RESUELVE?
   --------------
   Para que tu formulario sea rápido y “inteligente”, necesitas saber:
   - El Municipio actual (Código, Nombre, Activo)
   - El Estado actual al que pertenece
   - El País actual al que pertenece ese Estado

   Con esta info tu frontend puede:
   - Precargar inputs: Codigo_Municipio y Nombre_Municipio
   - Preseleccionar -- DROPdown País con Id_Pais actual
   - Preseleccionar -- DROPdown Estado con Id_Estado actual

   ¿POR QUÉ NO USAR UNA VISTA AQUÍ?
   -------------------------------
   Podrías usar una vista, pero un SP te da:
   - Validaciones más claras (si no existe el municipio, error controlado)
   - Un único contrato para el frontend
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ConsultarMunicipioEspecifico$$
CREATE PROCEDURE SP_ConsultarMunicipioEspecifico(
    IN _Id_Municipio INT
)
BEGIN
    /* ------------------------------------------------------------
       VALIDACIÓN 1: Id válido
       - Evita llamadas con NULL, 0, negativos, etc.
    ------------------------------------------------------------ */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    /* ------------------------------------------------------------
       VALIDACIÓN 2: El municipio existe
       - Si no existe, no tiene sentido cargar el formulario
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;

    /* ------------------------------------------------------------
       CONSULTA PRINCIPAL
       - Trae Municipio + Estado + País actual
       - LIMIT 1 por seguridad
    ------------------------------------------------------------ */
    SELECT
        Mun.Id_Municipio,
        Mun.Codigo  AS Codigo_Municipio,
        Mun.Nombre  AS Nombre_Municipio,
        
        Mun.Fk_Id_Estado AS Id_Estado,
        Est.Codigo  AS Codigo_Estado,
        Est.Nombre  AS Nombre_Estado,
        
        Est.Fk_Id_Pais AS Id_Pais,
        Pais.Codigo AS Codigo_Pais,
        Pais.Nombre AS Nombre_Pais,
        
        Mun.Activo  AS Activo_Municipio,
        Mun.created_at AS Created_at_Municipio,
        Mun.updated_at AS Updated_at_Municipio

    FROM Municipio Mun
    JOIN Estado Est  ON Est.Id_Estado = Mun.Fk_Id_Estado
    JOIN Pais Pais   ON Pais.Id_Pais  = Est.Fk_Id_Pais
    WHERE Mun.Id_Municipio = _Id_Municipio
    LIMIT 1;
END$$
DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPaisesActivos
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Para llenar el -- DROPdown de Países.

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO países activos (Activo = 1)
   - Ordenados por Nombre para que el usuario encuentre rápido.

   NOTA DE DISEÑO
   --------------
   - Si en tu UI quieres mostrar también inactivos (solo para admin),
     podrías hacer otro SP aparte: SP_ListarPaises(Todos/Activos)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarPaisesActivos$$
CREATE PROCEDURE SP_ListarPaisesActivos()
BEGIN
    SELECT
        Id_Pais,
        Codigo,
        Nombre
    FROM Pais
    WHERE Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstadosPorPais
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Al abrir el formulario, con el Id_Pais actual (para cargar estados del país actual)
   - Cada vez que el usuario cambia el País en el -- DROPdown

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO estados activos del país seleccionado
   - Esto permite la cascada País -> Estado:
       Seleccionas País -> te lista Estados de ese país

   VALIDACIONES
   ------------
   - El Id_Pais debe ser válido y existir para no devolver listas vacías “por error”
============================================================================================ */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS SP_ListarEstadosPorPais$$
CREATE PROCEDURE SP_ListarEstadosPorPais(
    IN _Id_Pais INT
)
BEGIN
    /* Validar Id */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* Validar que exista el país */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* Lista Estados activos del país */
    SELECT
        Id_Estado,
        Codigo,
        Nombre
    FROM Estado
    WHERE Fk_Id_Pais = _Id_Pais
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$
DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarMunicipiosPorEstado
   ============================================================================================
   OBJETIVO
   --------
   Llenar -- DROPdown de Municipios filtrado por Estado (solo Activo=1).
   Se usará después en otras tablas/pantallas donde selecciones municipio a partir del estado.

   REGLA
   -----
   - Solo municipios activos.
   - Ordenados por Nombre.
============================================================================================ */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS SP_ListarMunicipiosPorEstado$$
CREATE PROCEDURE SP_ListarMunicipiosPorEstado(
    IN _Id_Estado INT
)
BEGIN
    /* Validación: Id_Estado válido */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* Validación: Estado existe */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* Lista municipios activos del estado */
    SELECT
        Id_Municipio,
        Codigo,
        Nombre
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

 /* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarMunicipio
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Municipio dentro de un Estado específico, con blindaje fuerte:
   - Dentro del mismo Estado:
       * Si existe por CÓDIGO, el NOMBRE debe coincidir (si no, error).
       * Si existe por NOMBRE, el CÓDIGO debe coincidir (si no, error).
   - Si existe pero está Activo=0, se REACTIVA.
   - Si existe y está Activo=1, se bloquea el alta (error controlado).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario "Alta de Municipio" seleccionando un País (para filtrar) y un Estado.

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   1) Normaliza inputs (TRIM + NULLIF).
   2) Valida obligatorios.
   3) Valida que el País exista y esté ACTIVO (si tu UI manda País).
   4) Valida que el Estado exista, esté ACTIVO y pertenezca al País seleccionado.
   5) Busca por CÓDIGO dentro del Estado:
      - Si existe: valida NOMBRE; reactiva si Activo=0; si Activo=1 -> error.
   6) Si no existe por CÓDIGO, busca por NOMBRE dentro del Estado:
      - Si existe: valida CÓDIGO; reactiva si Activo=0; si Activo=1 -> error.
   7) Si no existe: INSERT.

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - TRANSACTION + HANDLERS (SQLEXCEPTION + 1062).
   - SELECT ... FOR UPDATE para serializar cuando la fila exista.
   - UNIQUE (Codigo,Fk_Id_Estado) y (Nombre,Fk_Id_Estado) como candado final.

   RESULTADO
   ---------
   Retorna:
   - Mensaje
   - Id_Municipio
   - Id_Estado
   - Accion: 'CREADA' | 'REACTIVADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarMunicipio$$
CREATE PROCEDURE SP_RegistrarMunicipio(
    IN _Codigo VARCHAR(50),
    IN _Nombre VARCHAR(255),
    IN _Id_Pais_Seleccionado INT,
    IN _Id_Estado INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Municipio INT DEFAULT NULL;
    DECLARE v_Codigo VARCHAR(50);
    DECLARE v_Nombre VARCHAR(255);
    DECLARE v_Activo TINYINT(1);

    /* ----------------------------------------------------------------------------------------
       MANEJO DE ERRORES
    ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Duplicado por concurrencia o restricción UNIQUE. Refresca y reintenta.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN
    ---------------------------------------------------------------------------------------- */
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES
    ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Municipio son obligatorios.';
    END IF;

    IF _Id_Pais_Seleccionado IS NULL OR _Id_Pais_Seleccionado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais seleccionado inválido.';
    END IF;

    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* País debe existir y estar activo */
    IF NOT EXISTS (
        SELECT 1
        FROM Pais
        WHERE Id_Pais = _Id_Pais_Seleccionado
          AND Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe o está inactivo.';
    END IF;

    /* Estado debe existir, estar activo y pertenecer al país seleccionado */
    IF NOT EXISTS (
        SELECT 1
        FROM Estado
        WHERE Id_Estado = _Id_Estado
          AND Fk_Id_Pais = _Id_Pais_Seleccionado
          AND Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe, está inactivo o no pertenece al País seleccionado.';
    END IF;

    START TRANSACTION;

    /* ========================================================================================
       1) BUSCAR POR CÓDIGO (DENTRO DEL ESTADO)
    ======================================================================================== */
    SET v_Id_Municipio = NULL;
    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Codigo = _Codigo
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Código ya existe pero el Nombre no coincide (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado exitosamente' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Municipio ACTIVO con ese Código en el Estado seleccionado.';
    END IF;

    /* ========================================================================================
       2) BUSCAR POR NOMBRE (DENTRO DEL ESTADO)
    ======================================================================================== */
    SET v_Id_Municipio = NULL;
    SELECT Id_Municipio, Codigo, Nombre, Activo
      INTO v_Id_Municipio, v_Codigo, v_Nombre, v_Activo
    FROM Municipio
    WHERE Nombre = _Nombre
      AND Fk_Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Municipio IS NOT NULL THEN
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Municipio. El Nombre ya existe pero el Código no coincide (en ese Estado).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Municipio
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Municipio = v_Id_Municipio;

            COMMIT;
            SELECT 'Municipio reactivado exitosamente' AS Mensaje,
                   v_Id_Municipio AS Id_Municipio,
                   _Id_Estado AS Id_Estado,
                   'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Municipio ACTIVO con ese Nombre en el Estado seleccionado.';
    END IF;

    /* ========================================================================================
       3) CREAR (NO EXISTE POR CÓDIGO NI POR NOMBRE EN ESE ESTADO)
    ======================================================================================== */
    INSERT INTO Municipio (Codigo, Nombre, Fk_Id_Estado, Activo)
    VALUES (_Codigo, _Nombre, _Id_Estado, 1);

    COMMIT;

    SELECT 'Municipio registrado exitosamente' AS Mensaje,
           LAST_INSERT_ID() AS Id_Municipio,
           _Id_Estado AS Id_Estado,
           'CREADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarMunicipio
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   Cuando el usuario da clic en "Guardar" en el formulario de edición de municipio.

   QUÉ PUEDE CAMBIAR ESTE SP
   -------------------------
   - Codigo del Municipio
   - Nombre del Municipio
   - Estado destino (mover el municipio a otro estado)

   QUÉ NO DEBE HACER ESTE SP (POR DISEÑO)
   --------------------------------------
   - NO crear Países
   - NO crear Estados
   - NO editar País/Estado (eso lo harás en otros formularios y SPs)

   POR QUÉ RECIBE Id_Pais_Seleccionado SI YA RECIBE Id_Estado_Destino
   ------------------------------------------------------------------
   - Porque tu UI permite filtrar estados por país.
   - En teoría si el frontend está bien, el estado elegido siempre pertenecerá a ese país.
   - PERO si hay un bug o alguien manipula la petición, podrías recibir un estado de otro país.
   - Entonces este SP valida:
        "el Estado destino pertenece al País seleccionado"
     y así “blinda” tu integridad lógica del formulario.

   BLINDAJES IMPORTANTES (EVITAR ERROR 1062)
   ----------------------------------------
   Tu tabla Municipio tiene UNIQUE:
     Uk_Municipio_Codigo_Estado  (Codigo, Fk_Id_Estado)
     Uk_Municipio_Estado         (Nombre, Fk_Id_Estado)

   Entonces antes de actualizar:
   - Revisa si ya existe OTRO municipio con el MISMO Codigo en el estado destino
   - Revisa si ya existe OTRO municipio con el MISMO Nombre en el estado destino
   - Excluye el mismo Id_Municipio (para permitir guardar sin cambios)

   TRANSACCIÓN
   -----------
   - Asegura que validaciones + update sean consistentes.
   - Si algo falla, rollback y RESIGNAL para que tu app lea el error real.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarMunicipio$$
CREATE PROCEDURE SP_EditarMunicipio(
    IN _Id_Municipio INT,
    IN _Codigo_Municipio VARCHAR(50),
    IN _Nombre_Municipio VARCHAR(255),
    IN _Id_Pais_Seleccionado INT,
    IN _Id_Estado_Destino INT
)
BEGIN
    DECLARE v_Estado_Actual INT DEFAULT NULL;

    /* Manejo de errores: si algo falla, revierte y lanza el error original */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ------------------------------------------------------------
       NORMALIZACIÓN
       - TRIM quita espacios para evitar “MIAMI ” vs “MIAMI”
       - NULLIF convierte '' a NULL para detectar vacíos con claridad
    ------------------------------------------------------------ */
    SET _Codigo_Municipio = NULLIF(TRIM(_Codigo_Municipio), '');
    SET _Nombre_Municipio = NULLIF(TRIM(_Nombre_Municipio), '');

    /* ------------------------------------------------------------
       VALIDACIONES DE NEGOCIO (FORMULARIO: TODO OBLIGATORIO)
    ------------------------------------------------------------ */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF _Codigo_Municipio IS NULL OR _Nombre_Municipio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre de Municipio son obligatorios.';
    END IF;

    IF _Id_Pais_Seleccionado IS NULL OR _Id_Pais_Seleccionado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: País seleccionado inválido.';
    END IF;

    IF _Id_Estado_Destino IS NULL OR _Id_Estado_Destino <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estado destino inválido.';
    END IF;

    START TRANSACTION;

    /* ------------------------------------------------------------
       PASO 0: Validar municipio y obtener Estado actual
       - Si el municipio no existe, se detiene.
    ------------------------------------------------------------ */
    SELECT Fk_Id_Estado
      INTO v_Estado_Actual
    FROM Municipio
    WHERE Id_Municipio = _Id_Municipio
    LIMIT 1;

    IF v_Estado_Actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;

    /* ------------------------------------------------------------
       PASO 1: Validar que exista el País seleccionado
    ------------------------------------------------------------ */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais_Seleccionado) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País seleccionado no existe.';
    END IF;

    /* ------------------------------------------------------------
       PASO 2: Validar que el Estado destino exista Y pertenezca al País
       - Este es el blindaje “País -> Estado” para que el frontend no mande combos inválidos.
    ------------------------------------------------------------ */
    IF NOT EXISTS (
        SELECT 1
        FROM Estado
        WHERE Id_Estado = _Id_Estado_Destino
          AND Fk_Id_Pais = _Id_Pais_Seleccionado
          AND Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: El Estado destino no pertenece al País seleccionado o está inactivo.';
    END IF;

    /* ------------------------------------------------------------
       PASO 3: BLINDAJE ANTI-DUPLICADOS (EVITAR 1062)
       - Validar Código duplicado en destino
       - Validar Nombre duplicado en destino
       - Excluir el mismo municipio
    ------------------------------------------------------------ */
    IF EXISTS (
        SELECT 1
        FROM Municipio
        WHERE Fk_Id_Estado = _Id_Estado_Destino
          AND Codigo = _Codigo_Municipio
          AND Id_Municipio <> _Id_Municipio
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Ya existe otro Municipio con ese CÓDIGO en el Estado destino.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Municipio
        WHERE Fk_Id_Estado = _Id_Estado_Destino
          AND Nombre = _Nombre_Municipio
          AND Id_Municipio <> _Id_Municipio
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Ya existe otro Municipio con ese NOMBRE en el Estado destino.';
    END IF;

    /* ------------------------------------------------------------
       PASO 4: UPDATE FINAL
       - Cambia Código, Nombre y mueve el municipio al Estado destino
       - updated_at se actualiza para auditoría básica
    ------------------------------------------------------------ */
    UPDATE Municipio
    SET
        Codigo = _Codigo_Municipio,
        Nombre = _Nombre_Municipio,
        Fk_Id_Estado = _Id_Estado_Destino,
        updated_at = NOW()
    WHERE Id_Municipio = _Id_Municipio;

    COMMIT;

    /* Respuesta para que el frontend confirme qué pasó */
    SELECT
        'Actualización Exitosa' AS Mensaje,
        _Id_Municipio AS Id_Municipio,
        v_Estado_Actual AS Id_Estado_Anterior,
        _Id_Estado_Destino AS Id_Estado_Nuevo;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusMunicipio
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un Municipio mediante:
     Municipio.Activo (1 = Activo / Visible, 0 = Inactivo / Borrado lógico)

   REGLA CRÍTICA (INTEGRIDAD / REFERENCIAS)
   ---------------------------------------
   - NO se permite DESACTIVAR (Activo=0) un Municipio si está siendo REFERENCIADO
     por cualquier otra tabla (hijos / dependencias).
   - Sí se permite REACTIVAR (Activo=1) siempre que el municipio exista.

   TABLAS QUE REFERENCIAN Municipio EN TU ESQUEMA (DE ACUERDO A LO QUE ME PASASTE)
   ------------------------------------------------------------------------------
   - Cat_Centros_Trabajo.Fk_Id_Municipio_CatCT  -> Municipio.Id_Municipio
   - Cat_Departamentos.Fk_Id_Municipio_CatDep  -> Municipio.Id_Municipio
   - Cat_Cases_Sedes.Fk_Id_Municipio           -> Municipio.Id_Municipio

   CONCURRENCIA
   ------------
   - Usamos TRANSACTION + SELECT ... FOR UPDATE sobre el Municipio para serializar
     cambios de estatus concurrentes.
   - Los checks a tablas hijas se hacen con EXISTS (LIMIT 1). No intentamos bloquear
     filas hijas porque aquí solo necesitamos saber si hay referencias.

   RESULTADO
   ---------
   - Si intenta desactivar y hay referencias -> ERROR controlado con el motivo.
   - Si aplica -> UPDATE Activo + updated_at y devuelve mensaje de éxito.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusMunicipio$$
CREATE PROCEDURE SP_CambiarEstatusMunicipio(
    IN _Id_Municipio INT,
    IN _Nuevo_Estatus TINYINT /* 1 = Activo, 0 = Inactivo */
)
BEGIN
    DECLARE v_Existe INT DEFAULT NULL;
    DECLARE v_Activo_Actual TINYINT(1) DEFAULT NULL;

    /* HANDLER general */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ------------------------------------------------------------
       VALIDACIONES DE PARÁMETROS
    ------------------------------------------------------------ */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* ------------------------------------------------------------
       1) VALIDAR EXISTENCIA DEL MUNICIPIO Y BLOQUEAR SU FILA
    ------------------------------------------------------------ */
    SELECT 1, Activo
      INTO v_Existe, v_Activo_Actual
    FROM Municipio
    WHERE Id_Municipio = _Id_Municipio
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Municipio no existe.';
    END IF;
    
        /* (Opcional) Si ya está inactivo, evita trabajo y devuelve mensaje claro */
    IF v_Activo_Actual = 0 THEN
		COMMIT;
        SELECT 'Sin cambios: El Municipio ya estaba Inactivo.' AS Mensaje;
        LEAVE SP;
	END IF;
    /* ------------------------------------------------------------
       2) SI INTENTA DESACTIVAR: BLOQUEAR SI TIENE REFERENCIAS
    ------------------------------------------------------------ */
    IF _Nuevo_Estatus = 0 THEN



        /* 2A) Referencias en Cat_Centros_Trabajo */
        IF EXISTS (
            SELECT 1
            FROM Cat_Centros_Trabajo
            WHERE Fk_Id_Municipio_CatCT = _Id_Municipio
            LIMIT 1
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Centros_Trabajo (Centros de Trabajo).';
        END IF;

        /* 2B) Referencias en Cat_Departamentos */
        IF EXISTS (
            SELECT 1
            FROM Cat_Departamentos
            WHERE Fk_Id_Municipio_CatDep = _Id_Municipio
            LIMIT 1
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Departamentos.';
        END IF;

        /* 2C) Referencias en Cat_Cases_Sedes */
        IF EXISTS (
            SELECT 1
            FROM Cat_Cases_Sedes
            WHERE Fk_Id_Municipio = _Id_Municipio
            LIMIT 1
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Municipio porque está referenciado por Cat_Cases_Sedes.';
        END IF;

    END IF;

    /* ------------------------------------------------------------
       3) APLICAR CAMBIO DE ESTATUS
    ------------------------------------------------------------ */
    UPDATE Municipio
    SET Activo = _Nuevo_Estatus,
        updated_at = NOW()
    WHERE Id_Municipio = _Id_Municipio;

    COMMIT;

    /* ------------------------------------------------------------
       4) RESPUESTA
    ------------------------------------------------------------ */
    IF _Nuevo_Estatus = 1 THEN
        SELECT 'Municipio Reactivado Exitosamente' AS Mensaje;
    ELSE
        SELECT 'Municipio Desactivado (Eliminado Lógico)' AS Mensaje;
    END IF;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarMunicipio
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente (DELETE) un Municipio.

   ¿CUÁNDO SE USA?
   --------------
   - Solo en administración avanzada, limpieza de datos o corrección controlada.
   - Normalmente NO se usa en operación diaria (para eso es el borrado lógico).

   RIESGOS / CANDADOS RECOMENDADOS
   -------------------------------
   - Si existe cualquier tabla que referencie Municipio (FK con NO ACTION),
     el DELETE fallará con error de integridad referencial.
   - Por seguridad, es recomendable agregar candados antes del DELETE, por ejemplo:
     - Bloquear si hay Cat_Centros_Trabajo ligados
     - Bloquear si hay Cat_Departamentos ligados
     - Bloquear si hay Cat_Cases_Sedes ligados
     (En tu esquema sí hay FKs hacia Municipio en varias tablas.)

   VALIDACIONES
   ------------
   - Verificar que el Id exista.
   - (Recomendado) Hacer el DELETE dentro de transacción y manejar excepciones con HANDLER,
     para devolver mensajes controlados si hay FKs que bloquean.

   RESPUESTA
   ---------
   - Devuelve un mensaje de confirmación si se eliminó.
============================================================================================ */

/* PROCEDIMIENTO DE ELIMINACION FISICA (BORRAR DEFINITIVAMENTE) */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarMunicipio$$
CREATE PROCEDURE SP_EliminarMunicipio(
    IN _Id_Municipio INT
)
BEGIN
    /* HANDLER FK: no se puede borrar si está referenciado */
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el Municipio porque está referenciado por otros registros (FK).';
    END;

    /* HANDLER general */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Municipio IS NULL OR _Id_Municipio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Municipio inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El ID del Municipio no existe.';
    END IF;

    START TRANSACTION;

    DELETE FROM Municipio
    WHERE Id_Municipio = _Id_Municipio;

    COMMIT;

    SELECT 'Municipio Eliminado Permanentemente' AS Mensaje;
END$$

DELIMITER ;
/* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarPais
   ============================================================================================
   OBJETIVO
   --------
   Registrar una nueva fila en Pais con blindaje fuerte contra duplicados y conflictos:
   - Si ya existe por CÓDIGO, el NOMBRE debe coincidir (si no, error).
   - Si ya existe por NOMBRE, el CÓDIGO debe coincidir (si no, error).
   - Si existe pero está Activo=0, se REACTIVA.
   - Si existe y está Activo=1, se bloquea el alta (error controlado).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario "Alta de País" (catálogo).

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   1) Normaliza inputs (TRIM + NULLIF).
   2) Valida obligatorios.
   3) Busca por CÓDIGO:
      - Si existe: valida NOMBRE.
        - Si Activo=0: Reactiva
        - Si Activo=1: Error (ya existe)
   4) Si no existe por CÓDIGO, busca por NOMBRE:
      - Si existe: valida CÓDIGO.
        - Si Activo=0: Reactiva
        - Si Activo=1: Error (ya existe)
   5) Si no existe: INSERT.

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - TRANSACTION + HANDLERS (SQLEXCEPTION + 1062).
   - SELECT ... FOR UPDATE para serializar cuando la fila exista.
   - UNIQUE en tabla sigue siendo la última línea de defensa.

   RESULTADO
   ---------
   Retorna:
   - Mensaje
   - Id_Pais
   - Accion: 'CREADA' | 'REACTIVADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarPais$$
CREATE PROCEDURE SP_RegistrarPais(
    IN _Codigo VARCHAR(50),
    IN _Nombre VARCHAR(255)
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Pais INT DEFAULT NULL;
    DECLARE v_Codigo  VARCHAR(50);
    DECLARE v_Nombre  VARCHAR(255);
    DECLARE v_Activo  TINYINT(1);

    /* ----------------------------------------------------------------------------------------
       MANEJO DE ERRORES
    ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Duplicado por concurrencia o restricción UNIQUE. Refresca y reintenta.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN
    ---------------------------------------------------------------------------------------- */
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES
    ---------------------------------------------------------------------------------------- */
    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del País son obligatorios.';
    END IF;

    START TRANSACTION;

    /* ========================================================================================
       1) BUSCAR POR CÓDIGO (REGLA PRINCIPAL)
    ======================================================================================== */
    SET v_Id_Pais = NULL;
    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Codigo = _Codigo
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        /* Conflicto: mismo código pero distinto nombre */
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Código ya existe pero el Nombre no coincide.';
        END IF;

        /* Reactivar si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado exitosamente' AS Mensaje, v_Id_Pais AS Id_Pais, 'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        /* Ya existe activo: bloquear alta */
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un País ACTIVO con ese Código.';
    END IF;

    /* ========================================================================================
       2) BUSCAR POR NOMBRE (SEGUNDA REGLA)
    ======================================================================================== */
    SET v_Id_Pais = NULL;
    SELECT Id_Pais, Codigo, Nombre, Activo
      INTO v_Id_Pais, v_Codigo, v_Nombre, v_Activo
    FROM Pais
    WHERE Nombre = _Nombre
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Pais IS NOT NULL THEN
        /* Conflicto: mismo nombre pero distinto código */
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto País. El Nombre ya existe pero el Código no coincide.';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Pais
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Pais = v_Id_Pais;

            COMMIT;
            SELECT 'País reactivado exitosamente' AS Mensaje, v_Id_Pais AS Id_Pais, 'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un País ACTIVO con ese Nombre.';
    END IF;

    /* ========================================================================================
       3) CREAR (NO EXISTE POR CÓDIGO NI POR NOMBRE)
    ======================================================================================== */
    INSERT INTO Pais (Codigo, Nombre, Activo)
    VALUES (_Codigo, _Nombre, 1);

    COMMIT;

    SELECT 'País registrado exitosamente' AS Mensaje, LAST_INSERT_ID() AS Id_Pais, 'CREADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarPais
   ============================================================================================
   OBJETIVO
   --------
   Editar Código y Nombre de un País con blindaje contra duplicados.

   PATRÓN (CONCURRENCIA SEGURA)
   ----------------------------
   1) Validar que el Id exista (FOR UPDATE).
   2) Validar no duplicidad por Código en otro Id (FOR UPDATE).
   3) Validar no duplicidad por Nombre en otro Id (FOR UPDATE).
   4) UPDATE.

   NOTAS
   -----
   - Permite editar aunque el País esté inactivo (admin/limpieza).
   - No cambia jerarquía por sí mismo (Estados referencian por Id).
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarPais$$
CREATE PROCEDURE SP_EditarPais(
    IN _Id_Pais INT,
    IN _Nuevo_Codigo VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255)
)
BEGIN
    DECLARE v_Existe INT DEFAULT 0;
    DECLARE v_DupId INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Normalización */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* Validaciones básicas */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre son obligatorios.';
    END IF;

    START TRANSACTION;

    /* 1) Validar existencia (FOR UPDATE) */
    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL OR v_Existe <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* 2) No duplicidad por Código (otro Id) */
    SET v_DupId = NULL;
    SELECT Id_Pais
      INTO v_DupId
    FROM Pais
    WHERE Codigo = _Nuevo_Codigo
      AND Id_Pais <> _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO País con ese CÓDIGO.';
    END IF;

    /* 3) No duplicidad por Nombre (otro Id) */
    SET v_DupId = NULL;
    SELECT Id_Pais
      INTO v_DupId
    FROM Pais
    WHERE Nombre = _Nuevo_Nombre
      AND Id_Pais <> _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO País con ese NOMBRE.';
    END IF;

    /* 4) UPDATE */
    UPDATE Pais
    SET Codigo = _Nuevo_Codigo,
        Nombre = _Nuevo_Nombre,
        updated_at = NOW()
    WHERE Id_Pais = _Id_Pais;

    COMMIT;

    SELECT 'País actualizado correctamente' AS Mensaje, _Id_Pais AS Id_Pais;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusPais
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un País mediante:
      Pais.Activo (1 = activo, 0 = inactivo)

   REGLA CRÍTICA (INTEGRIDAD JERÁRQUICA)
   ------------------------------------
   - NO se permite desactivar un País si tiene HIJOS ACTIVOS.
     Esto evita quedar con jerarquía inconsistente como:
        Pais.Activo=0
        Estado.Activo=1
        Municipio.Activo=1

   CANDADOS / CONCURRENCIA
   -----------------------
   - Se hace SELECT ... FOR UPDATE sobre el País para:
       * Validar existencia de forma determinística.
       * Serializar cambios simultáneos.
   - Se hace verificación de hijos activos antes del UPDATE.

   RESULTADO
   ---------
   - Devuelve mensaje de éxito o error controlado explicando por qué se bloqueó.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusPais$$
CREATE PROCEDURE SP_CambiarEstatusPais(
    IN _Id_Pais INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    DECLARE v_Existe INT DEFAULT 0;
    DECLARE v_Tmp INT DEFAULT NULL;

    /* HANDLER general */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validaciones de parámetros */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* 1) Validar existencia del País (y bloquear fila) */
    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = _Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL OR v_Existe <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* 2) Si se pretende DESACTIVAR: bloquear si hay hijos activos */
    IF _Nuevo_Estatus = 0 THEN

        /* 2A) Bloqueo: Estados activos */
        SET v_Tmp = NULL;
        SELECT Id_Estado
          INTO v_Tmp
        FROM Estado
        WHERE Fk_Id_Pais = _Id_Pais
          AND Activo = 1
        LIMIT 1
        FOR UPDATE;

        IF v_Tmp IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el País porque tiene ESTADOS ACTIVOS. Desactiva primero los Estados.';
        END IF;

        /* 2B) Blindaje extra (por si hubiera datos sucios): Municipios activos bajo el País */
        SET v_Tmp = NULL;
        SELECT Mun.Id_Municipio
          INTO v_Tmp
        FROM Municipio Mun
        JOIN Estado Est ON Est.Id_Estado = Mun.Fk_Id_Estado
        WHERE Est.Fk_Id_Pais = _Id_Pais
          AND Mun.Activo = 1
        LIMIT 1
        FOR UPDATE;

        IF v_Tmp IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el País porque existen MUNICIPIOS ACTIVOS bajo él. Desactiva primero los Municipios/Estados.';
        END IF;

    END IF;

    /* 3) Aplicar cambio */
    UPDATE Pais
    SET Activo = _Nuevo_Estatus,
        updated_at = NOW()
    WHERE Id_Pais = _Id_Pais;

    COMMIT;

    IF _Nuevo_Estatus = 1 THEN
        SELECT 'País Reactivado' AS Mensaje;
    ELSE
        SELECT 'País Desactivado (Oculto)' AS Mensaje;
    END IF;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarPaisFisico
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente un País, solo si está “limpio” (sin Estados asociados).

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada de catálogo (muy raro en producción).
   - Corrección de carga histórica errónea si no tiene dependencias.

   CANDADO DE SEGURIDAD
   --------------------
   - Si existe al menos un Estado con Fk_Id_Pais = _Id_Pais, se bloquea el DELETE.
   - Esto evita:
     - Romper la jerarquía País -> Estado -> Municipio
     - Errores de integridad referencial

   VALIDACIONES
   ------------
   - El País debe existir.
   - Debe no tener hijos (Estado).
   - (Recomendado) Manejo de errores con HANDLER si luego agregas más dependencias.

   RESPUESTA
   ---------
   - Mensaje de confirmación si se eliminó.
============================================================================================ */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarPaisFisico$$
CREATE PROCEDURE SP_EliminarPaisFisico(
    IN _Id_Pais INT
)
BEGIN
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el País porque está referenciado por otros registros (FK).';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* Candado: no debe tener estados */
    IF EXISTS(SELECT 1 FROM Estado WHERE Fk_Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el País porque tiene ESTADOS asociados. Elimine primero los estados.';
    END IF;

    START TRANSACTION;

    DELETE FROM Pais
    WHERE Id_Pais = _Id_Pais;

    COMMIT;

    SELECT 'País eliminado permanentemente' AS Mensaje;
END$$

DELIMITER ;


 /* ============================================================================================
   PROCEDIMIENTO: SP_RegistrarEstado
   ============================================================================================
   OBJETIVO
   --------
   Registrar un nuevo Estado dentro de un País específico, con blindaje fuerte:
   - Dentro del mismo País:
       * Si existe por CÓDIGO, el NOMBRE debe coincidir (si no, error).
       * Si existe por NOMBRE, el CÓDIGO debe coincidir (si no, error).
   - Si existe pero está Activo=0, se REACTIVA.
   - Si existe y está Activo=1, se bloquea el alta (error controlado).

   ¿CUÁNDO SE USA?
   --------------
   - Formulario "Alta de Estado" (catálogo) seleccionando un País.

   QUÉ HACE (CONTRATO DE NEGOCIO)
   ------------------------------
   1) Normaliza inputs (TRIM + NULLIF).
   2) Valida obligatorios.
   3) Valida que el País padre exista y esté ACTIVO.
   4) Busca por CÓDIGO dentro del País:
      - Si existe: valida NOMBRE; reactiva si Activo=0; si Activo=1 -> error.
   5) Si no existe por CÓDIGO, busca por NOMBRE dentro del País:
      - Si existe: valida CÓDIGO; reactiva si Activo=0; si Activo=1 -> error.
   6) Si no existe: INSERT.

   SEGURIDAD / INTEGRIDAD
   ----------------------
   - TRANSACTION + HANDLERS (SQLEXCEPTION + 1062).
   - SELECT ... FOR UPDATE para serializar cuando la fila exista.
   - UNIQUE (Codigo,Fk_Id_Pais) y (Nombre,Fk_Id_Pais) como candado final.

   RESULTADO
   ---------
   Retorna:
   - Mensaje
   - Id_Estado
   - Id_Pais
   - Accion: 'CREADA' | 'REACTIVADA'
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_RegistrarEstado$$
CREATE PROCEDURE SP_RegistrarEstado(
    IN _Codigo     VARCHAR(50),
    IN _Nombre     VARCHAR(255),
    IN _Fk_Id_Pais INT
)
SP: BEGIN
    /* ----------------------------------------------------------------------------------------
       VARIABLES INTERNAS
    ---------------------------------------------------------------------------------------- */
    DECLARE v_Id_Estado INT DEFAULT NULL;
    DECLARE v_Codigo    VARCHAR(50);
    DECLARE v_Nombre    VARCHAR(255);
    DECLARE v_Activo    TINYINT(1);

    /* ----------------------------------------------------------------------------------------
       MANEJO DE ERRORES
    ---------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Duplicado por concurrencia o restricción UNIQUE. Refresca y reintenta.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* ----------------------------------------------------------------------------------------
       NORMALIZACIÓN
    ---------------------------------------------------------------------------------------- */
    SET _Codigo = NULLIF(TRIM(_Codigo), '');
    SET _Nombre = NULLIF(TRIM(_Nombre), '');

    /* ----------------------------------------------------------------------------------------
       VALIDACIONES
    ---------------------------------------------------------------------------------------- */
    IF _Fk_Id_Pais IS NULL OR _Fk_Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    IF _Codigo IS NULL OR _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Estado son obligatorios.';
    END IF;

    /* País padre debe existir y estar activo (misma lógica que organización) */
    IF NOT EXISTS (
        SELECT 1
        FROM Pais
        WHERE Id_Pais = _Fk_Id_Pais
          AND Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe o está inactivo.';
    END IF;

    START TRANSACTION;

    /* ========================================================================================
       1) BUSCAR POR CÓDIGO (DENTRO DEL PAÍS)
    ======================================================================================== */
    SET v_Id_Estado = NULL;
    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Codigo = _Codigo
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        IF v_Nombre <> _Nombre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Código ya existe pero el Nombre no coincide (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado exitosamente' AS Mensaje, v_Id_Estado AS Id_Estado, _Fk_Id_Pais AS Id_Pais, 'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Estado ACTIVO con ese Código en el País seleccionado.';
    END IF;

    /* ========================================================================================
       2) BUSCAR POR NOMBRE (DENTRO DEL PAÍS)
    ======================================================================================== */
    SET v_Id_Estado = NULL;
    SELECT Id_Estado, Codigo, Nombre, Activo
      INTO v_Id_Estado, v_Codigo, v_Nombre, v_Activo
    FROM Estado
    WHERE Nombre = _Nombre
      AND Fk_Id_Pais = _Fk_Id_Pais
    LIMIT 1
    FOR UPDATE;

    IF v_Id_Estado IS NOT NULL THEN
        IF v_Codigo <> _Codigo THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'ERROR: Conflicto Estado. El Nombre ya existe pero el Código no coincide (en ese País).';
        END IF;

        IF v_Activo = 0 THEN
            UPDATE Estado
            SET Activo = 1, updated_at = NOW()
            WHERE Id_Estado = v_Id_Estado;

            COMMIT;
            SELECT 'Estado reactivado exitosamente' AS Mensaje, v_Id_Estado AS Id_Estado, _Fk_Id_Pais AS Id_Pais, 'REACTIVADA' AS Accion;
            LEAVE SP;
        END IF;

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe un Estado ACTIVO con ese Nombre en el País seleccionado.';
    END IF;

    /* ========================================================================================
       3) CREAR (NO EXISTE POR CÓDIGO NI POR NOMBRE EN ESE PAÍS)
    ======================================================================================== */
    INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais, Activo)
    VALUES (_Codigo, _Nombre, _Fk_Id_Pais, 1);

    COMMIT;

    SELECT 'Estado registrado exitosamente' AS Mensaje, LAST_INSERT_ID() AS Id_Estado, _Fk_Id_Pais AS Id_Pais, 'CREADA' AS Accion;

END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EditarEstado
   ============================================================================================
   OBJETIVO
   --------
   Editar Código/Nombre de un Estado y (opcional) moverlo a otro País.

   PATRÓN (CONCURRENCIA SEGURA)
   ----------------------------
   1) Validar que el Id exista (FOR UPDATE).
   2) Validar que el País destino exista (FOR UPDATE) y (por UI dropdown) esté activo.
   3) Validar no duplicidad por Código en el País destino (FOR UPDATE).
   4) Validar no duplicidad por Nombre en el País destino (FOR UPDATE).
   5) UPDATE.

   NOTA DE NEGOCIO
   --------------
   - Mover Estado de País mueve “indirectamente” sus Municipios (porque siguen apuntando al Estado).
   - Si NO quieres permitir mover cuando haya Municipios, agrega un candado extra.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EditarEstado$$
CREATE PROCEDURE SP_EditarEstado(
    IN _Id_Estado INT,
    IN _Nuevo_Codigo VARCHAR(50),
    IN _Nuevo_Nombre VARCHAR(255),
    IN _Nuevo_Id_Pais INT
)
BEGIN
    DECLARE v_Existe INT DEFAULT 0;
    DECLARE v_DupId INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Normalización */
    SET _Nuevo_Codigo = NULLIF(TRIM(_Nuevo_Codigo), '');
    SET _Nuevo_Nombre = NULLIF(TRIM(_Nuevo_Nombre), '');

    /* Validaciones */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF _Nuevo_Id_Pais IS NULL OR _Nuevo_Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Pais destino inválido.';
    END IF;

    IF _Nuevo_Codigo IS NULL OR _Nuevo_Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Código y Nombre del Estado son obligatorios.';
    END IF;

    START TRANSACTION;

    /* 1) Validar existencia del Estado (FOR UPDATE) */
    SELECT 1
      INTO v_Existe
    FROM Estado
    WHERE Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL OR v_Existe <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* 2) Validar País destino (FOR UPDATE) */
    SELECT 1
      INTO v_Existe
    FROM Pais
    WHERE Id_Pais = _Nuevo_Id_Pais
      AND Activo = 1
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL OR v_Existe <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País destino no existe o está inactivo.';
    END IF;

    /* 3) No duplicidad por Código en País destino */
    SET v_DupId = NULL;
    SELECT Id_Estado
      INTO v_DupId
    FROM Estado
    WHERE Fk_Id_Pais = _Nuevo_Id_Pais
      AND Codigo = _Nuevo_Codigo
      AND Id_Estado <> _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Estado con ese CÓDIGO en el País destino.';
    END IF;

    /* 4) No duplicidad por Nombre en País destino */
    SET v_DupId = NULL;
    SELECT Id_Estado
      INTO v_DupId
    FROM Estado
    WHERE Fk_Id_Pais = _Nuevo_Id_Pais
      AND Nombre = _Nuevo_Nombre
      AND Id_Estado <> _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_DupId IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Ya existe OTRO Estado con ese NOMBRE en el País destino.';
    END IF;

    /* 5) UPDATE */
    UPDATE Estado
    SET Codigo = _Nuevo_Codigo,
        Nombre = _Nuevo_Nombre,
        Fk_Id_Pais = _Nuevo_Id_Pais,
        updated_at = NOW()
    WHERE Id_Estado = _Id_Estado;

    COMMIT;

    SELECT 'Estado actualizado correctamente' AS Mensaje, _Id_Estado AS Id_Estado, _Nuevo_Id_Pais AS Id_Pais;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusEstado
   ============================================================================================
   OBJETIVO
   --------
   Activar/Desactivar (borrado lógico) un Estado mediante:
      Estado.Activo (1 = activo, 0 = inactivo)

   REGLA CRÍTICA (INTEGRIDAD JERÁRQUICA)
   ------------------------------------
   - NO se permite desactivar un Estado si tiene MUNICIPIOS ACTIVOS.
     Evita inconsistencia:
        Estado.Activo=0
        Municipio.Activo=1

   CANDADOS / CONCURRENCIA
   -----------------------
   - SELECT ... FOR UPDATE sobre el Estado (existencia y serialización).
   - Verificación de hijos activos antes del UPDATE.

   RESULTADO
   ---------
   - Devuelve mensaje de éxito o error controlado explicando bloqueo.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_CambiarEstatusEstado$$
CREATE PROCEDURE SP_CambiarEstatusEstado(
    IN _Id_Estado INT,
    IN _Nuevo_Estatus TINYINT -- 1 = Activo, 0 = Inactivo
)
BEGIN
    DECLARE v_Existe INT DEFAULT 0;
    DECLARE v_Tmp INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF _Nuevo_Estatus NOT IN (0,1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Estatus inválido (solo 0 o 1).';
    END IF;

    START TRANSACTION;

    /* 1) Validar existencia del Estado (bloquea fila) */
    SELECT 1
      INTO v_Existe
    FROM Estado
    WHERE Id_Estado = _Id_Estado
    LIMIT 1
    FOR UPDATE;

    IF v_Existe IS NULL OR v_Existe <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* 2) Si se pretende DESACTIVAR: bloquear si hay municipios activos */
    IF _Nuevo_Estatus = 0 THEN
        SET v_Tmp = NULL;
        SELECT Id_Municipio
          INTO v_Tmp
        FROM Municipio
        WHERE Fk_Id_Estado = _Id_Estado
          AND Activo = 1
        LIMIT 1
        FOR UPDATE;

        IF v_Tmp IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BLOQUEADO: No se puede desactivar el Estado porque tiene MUNICIPIOS ACTIVOS. Desactiva primero los Municipios.';
        END IF;
    END IF;

    /* 3) Aplicar cambio */
    UPDATE Estado
    SET Activo = _Nuevo_Estatus,
        updated_at = NOW()
    WHERE Id_Estado = _Id_Estado;

    COMMIT;

    IF _Nuevo_Estatus = 1 THEN
        SELECT 'Estado Reactivado' AS Mensaje;
    ELSE
        SELECT 'Estado Desactivado' AS Mensaje;
    END IF;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarEstadoFisico
   ============================================================================================
   OBJETIVO
   --------
   Eliminar físicamente un Estado, solo si NO tiene Municipios asociados.

   ¿CUÁNDO SE USA?
   --------------
   - Limpieza controlada (muy raro en producción).
   - Correcciones cuando el Estado fue creado por error y aún no tiene hijos.

   CANDADO DE SEGURIDAD
   --------------------
   - Si existe al menos un Municipio con Fk_Id_Estado = _Id_Estado, se bloquea el DELETE.
   - Evita romper la integridad del catálogo.

   VALIDACIONES
   ------------
   - Estado debe existir.
   - No debe tener Municipios asociados.

   RESPUESTA
   ---------
   - Mensaje de confirmación si se elimina.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_EliminarEstadoFisico$$
CREATE PROCEDURE SP_EliminarEstadoFisico(
    IN _Id_Estado INT
)
BEGIN
    DECLARE EXIT HANDLER FOR 1451
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: No se puede eliminar el Estado porque está referenciado por otros registros (FK).';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    /* Validación */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    IF NOT EXISTS(SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* Candado: no debe tener municipios */
    IF EXISTS(SELECT 1 FROM Municipio WHERE Fk_Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR CRÍTICO: No se puede eliminar el Estado porque tiene MUNICIPIOS asociados.';
    END IF;

    START TRANSACTION;

    DELETE FROM Estado
    WHERE Id_Estado = _Id_Estado;

    COMMIT;

    SELECT 'Estado eliminado permanentemente' AS Mensaje;
END$$

DELIMITER ;
