use Picade;

/* ------------------------------------------------------------------------------------------------------ */
/* CREACION DE VISTAS Y PROCEDIMIENTO DE ALMACENADO PARA LA BASE DE DATOS*/
/* ------------------------------------------------------------------------------------------------------ */
CREATE 
    ALGORITHM = UNDEFINED 
    DEFINER = `root`@`localhost` 
    SQL SECURITY DEFINER
VIEW `Picade`.`Vista_Direcciones` AS
    SELECT 
        `picade.mun`.`Id_Municipio` AS `Id_Municipio`,
        `picade.mun`.`Codigo` AS `Codigo_Municipio`,
        `picade.mun`.`Nombre` AS `Nombre_Municipio`,
        `picade.est`.`Codigo` AS `Codigo_Estado`,
        `picade.est`.`Nombre` AS `Nombre_Estado`,
        `picade.pais`.`Codigo` AS `Codigo_Pais`,
        `picade.pais`.`Nombre` AS `Nombre_Pais`,
        `picade.mun`.`Activo` AS `Estatus`
    FROM
        ((`picade`.`municipio` `picade.mun`
        JOIN `picade`.`estado` `picade.est` ON (`picade.mun`.`Fk_Id_Estado` = `picade.est`.`Id_Estado`))
        JOIN `picade`.`pais` `picade.pais` ON (`picade.est`.`Fk_Id_Pais` = `picade.pais`.`Id_Pais`))
    LIMIT 0 , 3000

/* ------------------------------------------------------------------------------------------------------ */
/* PROCEDIMEINTO DE ALMACENADOS PARA LAS UBICACIONES/DIRECCIONES */

DELIMITER //

DROP PROCEDURE IF EXISTS SP_BuscadorGlobalUbicaciones; -- Borramos el anterior para no duplicar

CREATE PROCEDURE SP_BuscadorGlobalUbicaciones(
    IN _textoBusqueda VARCHAR(150)
)
BEGIN
    -- Limpiamos espacios en blanco al inicio/final por si el usuario se equivoca
    SET _textoBusqueda = TRIM(_textoBusqueda);

    -- Si el buscador está vacío, devolvemos los primeros 50 registros para llenar la tabla
    IF _textoBusqueda = '' OR _textoBusqueda IS NULL THEN
        SELECT * FROM `Picade`.`Vista_Direcciones` 
        WHERE Estatus = 1 
        LIMIT 50; 
    
    ELSE
        -- AQUÍ ESTÁ LA MAGIA:
        -- Usamos CONCAT para rodear la palabra con símbolos de porcentaje (%)
        -- El operador OR dice: "Si coincide con el Municipio O con el Estado O con el País, tráelo".
        
        SELECT * FROM `Picade`.`Vista_Direcciones`
        WHERE Estatus = 1 
        AND (
			-- AQUI ESTABA EL DETALLE: Usar los alias de la VISTA
            Codigo_Municipio LIKE CONCAT('%', _textoBusqueda, '%') OR -- Agregué código por si acaso
            Nombre_Municipio LIKE CONCAT('%', _textoBusqueda, '%') OR
            Codigo_Estado	 LIKE CONCAT('%', _textoBusqueda, '%') OR -- Agregué código por si acaso
            Nombre_Estado    LIKE CONCAT('%', _textoBusqueda, '%') OR
            Codigo_Pais		 LIKE CONCAT('%', _textoBusqueda, '%') OR -- Agregué código por si acaso
            Nombre_Pais      LIKE CONCAT('%', _textoBusqueda, '%') 
        );
    END IF;

END //
DELIMITER ;

/* ------------------------------------------------------------------------------------------------------ 
*¨LLAMADA AL PROCEDIMIENTO DE BUSQUEDA DESDE EL BUSCADOR*/
CALL SP_BuscadorGlobalUbicaciones('ver');

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

/* PROCEDIMIENTO DE REGISTRO DE UNA NUEVA UBICACION/DIRECCION*/
DELIMITER //

DROP PROCEDURE IF EXISTS SP_RegistrarUbicacionCompleta;

CREATE PROCEDURE SP_RegistrarUbicacionCompleta(
	IN _Codigo_Municipio VARCHAR(50), -- Datos del Municipio (El nuevo) Puede ser vacío si no tienes
    IN _Nombre_Municipio VARCHAR(255),
	IN _Codigo_Estado VARCHAR(50),-- Datos del Estado
    IN _Nombre_Estado VARCHAR(255),
    IN _Codigo_Pais VARCHAR(50),-- Datos del Pais
    IN _Nombre_Pais VARCHAR(255)

)
BEGIN
    -- Variables para guardar los IDs
    DECLARE v_Id_Pais INT;
    DECLARE v_Id_Estado INT;
    /* --------------------------------------------------------- */
    -- 1. NIVEL PAIS
    -- Buscamos si ya existe el país por su código (ej: MEX)
    /* --------------------------------------------------------- */
    SELECT Id_Pais INTO v_Id_Pais FROM Pais WHERE Codigo = _Codigo_Pais LIMIT 1;

    -- Si no existe (es NULL), lo creamos
    IF v_Id_Pais IS NULL THEN
        INSERT INTO Pais (Codigo, Nombre, Activo) VALUES (_Codigo_Pais, _Nombre_Pais, 1);
        SET v_Id_Pais = LAST_INSERT_ID();
    END IF;

    /* --------------------------------------------------------- */
    -- 2. NIVEL ESTADO
    -- Buscamos si existe el estado dentro de ese país
    /* --------------------------------------------------------- */
    SELECT Id_Estado INTO v_Id_Estado FROM Estado 
    WHERE Codigo = _Codigo_Estado AND Fk_Id_Pais = v_Id_Pais LIMIT 1;

    -- Si no existe, lo creamos y lo vinculamos al País detectado
    IF v_Id_Estado IS NULL THEN
        INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais, Activo) 
        VALUES (_Codigo_Estado, _Nombre_Estado, v_Id_Pais, 1);
        SET v_Id_Estado = LAST_INSERT_ID();
    END IF;

    /* --------------------------------------------------------- */
    -- 3. NIVEL MUNICIPIO
    -- Finalmente insertamos el municipio vinculado al Estado detectado
    /* --------------------------------------------------------- */
    INSERT INTO Municipio (Codigo, Nombre, Fk_Id_Estado, Activo)
    VALUES (_Codigo_Municipio, _Nombre_Municipio, v_Id_Estado, 1);

    -- Devolvemos el mensaje de éxito
    SELECT 'Registro Exitoso' AS Mensaje, LAST_INSERT_ID() AS Id_Nuevo_Municipio;

END //
DELIMITER ;

/* ------------------------------------------------------------------------------------------------------ */
/* VALIDACIONES DE FUNCIONAMIENTO DEL PROCEDIMIENTO */
 
CALL SP_RegistrarUbicacionCompleta(
	'SHI', 'SHIBUYA', -- MINICIPIO
    'TOK', 'TOKIO', -- ESTADO
    'JPN', 'JAPÓN' -- PAIS
);

-- 1. Agregamos MINATO (Mismo estado TOKIO, Mismo país JAPÓN)
CALL SP_RegistrarUbicacionCompleta(
    'MIN', 'MINATO', -- MUNICIPIO
    'TOK', 'TOKIO',  -- ESTADO
    'JPN', 'JAPÓN'   -- PAIS
);

-- 2. Agregamos CHIYODA (Mismo estado TOKIO, Mismo país JAPÓN)
CALL SP_RegistrarUbicacionCompleta(
    'CHI', 'CHIYODA', -- MUNICIPIO
    'TOK', 'TOKIO',   -- ESTADO
    'JPN', 'JAPÓN'    -- PAIS
);

-- 3. Nuevo Estado: OSAKA -> Municipio: CIUDAD DE OSAKA
CALL SP_RegistrarUbicacionCompleta(
    'OSK', 'CIUDAD DE OSAKA', -- MUNICIPIO
    'OSA', 'OSAKA',           -- ESTADO
    'JPN', 'JAPÓN'            -- PAIS
);

-- 4. Mismo Estado Nuevo: OSAKA -> Municipio: SAKAI
CALL SP_RegistrarUbicacionCompleta(
    'SAK', 'SAKAI', -- MUNICIPIO
    'OSA', 'OSAKA', -- ESTADO
    'JPN', 'JAPÓN'  -- PAIS
);

-- 5. Nuevo Estado: KYOTO -> Municipio: CIUDAD DE KYOTO
CALL SP_RegistrarUbicacionCompleta(
    'KYC', 'CIUDAD DE KYOTO', -- MUNICIPIO
    'KYO', 'KYOTO',           -- ESTADO
    'JPN', 'JAPÓN'            -- PAIS
);

SELECT * FROM Vista_Direcciones WHERE Nombre_Municipio or Nombre_Estado or Nombre_Pais = 'JAPÓN';
CALL SP_BuscadorGlobalUbicaciones('Ja');

-- ORDEN: Mun, Est, Pais
CALL SP_RegistrarUbicacionCompleta(
    'MIA', 'MIAMI',          -- 1. Municipio
    'FL',  'FLORIDA',        -- 2. Estado
    'USA', 'ESTADOS UNIDOS'  -- 3. País
);
SELECT * FROM Vista_Direcciones WHERE Nombre_Municipio or Nombre_Estado or Nombre_Pais = 'FL';
CALL SP_BuscadorGlobalUbicaciones('FL');

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

/* PROCEDIMIENTO DE ALMACENADO PARA ACTULIZAR UN REGISTRO ESPECIFICO */
DELIMITER //

DROP PROCEDURE IF EXISTS SP_EditarUbicacionCompleta;

CREATE PROCEDURE SP_EditarUbicacionCompleta(
	-- EL ID ES CRUCIAL PARA SABER CUAL ACTUALIZAR
    IN _Id_Municipio_A_Editar INT,
    IN _Codigo_Municipio VARCHAR(50), -- 1. DATOS DEL MUNICIPIO
    IN _Nombre_Municipio VARCHAR(255), 
    IN _Codigo_Estado VARCHAR(50), -- 2. DATOS DEL ESTADO (Donde debe quedar asignado)
    IN _Nombre_Estado VARCHAR(255),
    IN _Codigo_Pais VARCHAR(50), -- 3. DATOS DEL PAIS (Donde debe quedar asignado)
    IN _Nombre_Pais VARCHAR(255)
)
BEGIN
	-- Variables internas
    DECLARE v_Id_Pais INT;
    DECLARE v_Id_Estado INT;
    
    -- PASO 0: VALIDAR QUE EL MUNICIPIO EXISTA
    IF NOT EXISTS(SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio_A_Editar) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El ID del Municipio no existe.';
    ELSE
		/* --------------------------------------------------------- */
        -- PASO 1: GESTIONAR EL PAIS (Igual que en el registro)
        /* --------------------------------------------------------- */
        SELECT Id_Pais INTO v_Id_Pais FROM Pais WHERE Codigo = _Codigo_Pais LIMIT 1;
        
        -- Si cambiaron el país a uno que no existe, lo creamos
        IF v_Id_Pais IS NULL THEN
            INSERT INTO Pais (Codigo, Nombre, Activo) VALUES (_Codigo_Pais, _Nombre_Pais, 1);
            SET v_Id_Pais = LAST_INSERT_ID();
        END IF;
        
        /* --------------------------------------------------------- */
        -- PASO 2: GESTIONAR EL ESTADO
        /* --------------------------------------------------------- */
        -- Buscamos el estado basándonos en el código y el país resuelto arriba
        SELECT Id_Estado INTO v_Id_Estado FROM Estado 
        WHERE Codigo = _Codigo_Estado AND Fk_Id_Pais = v_Id_Pais LIMIT 1;
        
        -- Si cambiaron el estado a uno que no existe, lo creamos
        IF v_Id_Estado IS NULL THEN
            INSERT INTO Estado (Codigo, Nombre, Fk_Id_Pais, Activo) 
            VALUES (_Codigo_Estado, _Nombre_Estado, v_Id_Pais, 1);
            SET v_Id_Estado = LAST_INSERT_ID();
        END IF;
        
        /* --------------------------------------------------------- */
        -- PASO 3: ACTUALIZAR EL MUNICIPIO
        /* --------------------------------------------------------- */
        -- Aquí actualizamos Nombre, Código y (muy importante) lo movemos de Estado si es necesario
        UPDATE Municipio 
        SET 
            Codigo = _Codigo_Municipio,
            Nombre = _Nombre_Municipio,
            Fk_Id_Estado = v_Id_Estado, -- Aquí vinculamos al ID detectado en el Paso 2
            updated_at = NOW()
        WHERE Id_Municipio = _Id_Municipio_A_Editar;

        SELECT 'Actualización Exitosa' AS Mensaje;
    END IF;

END //
DELIMITER ;

/*------------------------------------------------------------------------------------------------------ */
/* USO DEL PRODEDIMIENTO PARA ACTUALIZAR UN REGISTRO ESPECIFICO */

CALL SP_EditarUbicacionCompleta(
    2471,                   -- ID del registro a modificar
    'LAX', 'LOS ANGELES',   -- NUEVO Municipio (Código y Nombre)
    'CA',  'CALIFORNIA',    -- NUEVO Estado (Código y Nombre)
    'USA', 'ESTADOS UNIDOS' -- Mismo País
);

SELECT * FROM Vista_Direcciones WHERE Id_Municipio = 2471;
SELECT * FROM Picade.Municipio WHERE Id_Municipio = 2471;
CALL SP_BuscadorGlobalUbicaciones('Lax');

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

/* PROCEDIMIENTO PARA CAMBIAR ESTATUS (ACTIVAR / DESACTIVAR) */
DELIMITER //

DROP PROCEDURE IF EXISTS SP_CambiarEstatusMunicipio;

CREATE PROCEDURE SP_CambiarEstatusMunicipio(
    IN _Id_Municipio INT,
    IN _Nuevo_Estatus TINYINT /* 1 = Activo, 0 = Inactivo */
)
BEGIN
    -- Validamos si existe
    IF EXISTS(SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        
        UPDATE Municipio
        SET 
            Activo = _Nuevo_Estatus, -- Aquí asignamos lo que tú mandes (0 o 1)
            updated_at = NOW()
        WHERE Id_Municipio = _Id_Municipio;

        -- Mensaje dinámico según lo que hiciste
        IF _Nuevo_Estatus = 1 THEN
            SELECT 'Municipio Reactivado Exitosamente' AS Mensaje;
        ELSE
            SELECT 'Municipio Desactivado (Eliminado Lógico)' AS Mensaje;
        END IF;
    
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El ID del Municipio no existe.';
    END IF;

END //
DELIMITER ;

/* ------------------------------------------------------------------------------------------------------ */
/* USO DEL PROCEDIMIENTO PARA ACTIVAR O DESACTIVAR */
-- 1. Lo desactivamos
-- Mandas un 0 para "apagarlo"
CALL SP_CambiarEstatusMunicipio(2471, 0);

-- Mandas un 1 para "prenderlo" de nuevo
CALL SP_CambiarEstatusMunicipio(2471, 1);

-- 2. Intentamos buscarlo (NO debería aparecer)
CALL SP_BuscadorGlobalUbicaciones('LOS ANGELES');

-- 3. (Opcional) Verificamos que sigue en la tabla pero oculto
SELECT * FROM Municipio WHERE Id_Municipio = 2471; 
-- Verás que la columna 'Activo' ahora es 0.

/* ------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------- */

/* PROCEDIMIENTO DE ELIMINACION FISICA (BORRAR DEFINITIVAMENTE) */
DELIMITER //

DROP PROCEDURE IF EXISTS SP_EliminarMunicipioFisico;

CREATE PROCEDURE SP_EliminarMunicipioFisico(
    IN _Id_Municipio INT
)
BEGIN
    -- Validamos si existe
    IF EXISTS(SELECT 1 FROM Municipio WHERE Id_Municipio = _Id_Municipio) THEN
        
        DELETE FROM Municipio
        WHERE Id_Municipio = _Id_Municipio;

        SELECT 'Municipio Eliminado Permanentemente' AS Mensaje;
    
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: El ID del Municipio no existe.';
    END IF;

END //
DELIMITER ;

/* ------------------------------------------------------------------------------------------------------ */

/* USO DE PROCEDIMIENTO PARA ELIMINACION FISICA */
-- Borrado definitivo
CALL SP_EliminarMunicipioFisico(2471);

-- Verificamos (Ya no existirá ni buscando por ID directo)
SELECT * FROM Municipio WHERE Id_Municipio = 2471;
-- Resultado: Vacío.

/* ------------------------------------------------------------------------------------------------------ 
--------------------------------------------------------------------------------------------------------- */