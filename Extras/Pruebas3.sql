/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarPerfilPropio]
   ============================================================================================
   VERSIÓN: 1.6 (ENTITY-CENTRIC GROUPING)
   
   FILOSOFÍA DE DISEÑO:
   La información se devuelve agrupada por "Objeto de Negocio". 
   Ejemplo: Todo lo relacionado al Centro de Trabajo (ID, Nombre, Dirección, Ubicación Geográfica)
   se entrega en un bloque contiguo para facilitar la lectura y el debugging.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarPerfilPropio`$$
CREATE PROCEDURE `SP_ConsultarPerfilPropio`(
    IN _Id_Usuario_Sesion INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       VALIDACIÓN 1: Integridad de Sesión
       ---------------------------------------------------------------------------------------- */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SESIÓN: Identificador de usuario inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       VALIDACIÓN 2: Existencia del Usuario
       ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Sesion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO: El usuario solicitado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       CONSULTA PRINCIPAL
       ---------------------------------------------------------------------------------------- */
    SELECT 
        /* =================================================================================
           CONJUNTO 1: IDENTIDAD Y ACCESO
           ================================================================================= */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,
        `U`.`Email`,
        -- `U`.`Foto_Perfil_Url`,

        /* =================================================================================
           CONJUNTO 2: DATOS PERSONALES (INFO HUMANOS)
           ================================================================================= */
        `IP`.`Id_InfoPersonal`,
        /* Helper: Nombre Completo */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,

        /* =================================================================================
           CONJUNTO 3: RÉGIMEN CONTRACTUAL
           ================================================================================= */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`,
        `Reg`.`Codigo`            AS `Codigo_Regimen`,
        `Reg`.`Nombre`            AS `Nombre_Regimen`,

        /* =================================================================================
           CONJUNTO 4: PUESTO DE TRABAJO
           ================================================================================= */
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,
        `Puesto`.`Codigo`         AS `Codigo_Puesto`,
        `Puesto`.`Nombre`         AS `Nombre_Puesto`,

        /* =================================================================================
           CONJUNTO 5: CENTRO DE TRABAJO (CT) + SU GEOGRAFÍA
           ================================================================================= */
        `IP`.`Fk_Id_CatCT`        AS `Id_CentroTrabajo`,
        `CT`.`Codigo`             AS `Codigo_CentroTrabajo`,
        `CT`.`Nombre`             AS `Nombre_CentroTrabajo`,
        `CT`.`Direccion_Fisica`   AS `Direccion_Fisica_CT`,
        /* Ubicación Geográfica del CT (Para Dropdowns en Cascada) */
        `CT`.`Fk_Id_Municipio_CatCT` AS `Id_Municipio_CT`,
        `MunCT`.`Codigo`			AS `Codigo_Municipio_CT`,
        `MunCT`.`Nombre`			AS `Nombre_Municipio_CT`,
        `EdoCT`.`Id_Estado`          AS `Id_Estado_CT`,
        `EdoCT`.`Codigo`			AS `Codigo_Estado_CT`,
        -- `EdoCT`.`Nombre`			AS `Nombre_Estado_CT`,
        `PaisCT`.`Id_Pais`           AS `Id_Pais_CT`,
		`PaisCT`.`Codigo`			AS `Codigo_Pais_CT`,
        -- `PaisCT`.`Nombre`			AS `Nombre_Pais_CT`,

        /* =================================================================================
           CONJUNTO 6: DEPARTAMENTO + SU GEOGRAFÍA
           ================================================================================= */
        `IP`.`Fk_Id_CatDep`       AS `Id_Departamento`,
        `Dep`.`Codigo`            AS `Codigo_Departamento`,
        `Dep`.`Nombre`            AS `Nombre_Departamento`,
        `Dep`.`Direccion_Fisica`  AS `Direccion_Fisica_Depto`,
        /* Ubicación Geográfica del Depto (Para Dropdowns en Cascada) */
        `Dep`.`Fk_Id_Municipio_CatDep` AS `Id_Municipio_Depto`,
        `MunDep`.`Codigo`			AS `Codigo_Municipio_Depto`,
        `MunDep`.`Nombre`			AS `Nombre_Municipio_Depto`,
        `EdoDep`.`Id_Estado`          AS `Id_Estado_Depto`,
        `EdoDep`.`Codigo`			AS `Codigo_Estado_Depto`,
        -- `EdoDep`.`Nombre`			AS `Nombre_Estado_Depto`,
        `PaisDep`.`Id_Pais`           AS `Id_Pais_Depto`,
		`PaisDep`.`Codigo`			AS `Codigo_Pais_Depto`,
        -- `PaisDep`.`Nombre`			AS `Nombre_Pais_Depto`,

        /* =================================================================================
           CONJUNTO 7: REGIÓN
           ================================================================================= */
        `IP`.`Fk_Id_CatRegion`    AS `Id_Region`,
        `Region`.`Codigo`         AS `Codigo_Region`,
        `Region`.`Nombre`         AS `Nombre_Region`,

        /* =================================================================================
           CONJUNTO 8: JERARQUÍA ORGANIZACIONAL (Gerencia -> Subdirección -> Dirección)
           ================================================================================= */
        /* Nivel 1: Gerencia (Directo) */
        `IP`.`Fk_Id_CatGeren`     AS `Id_Gerencia`,
        `Ger`.`Clave`             AS `Clave_Gerencia`,
        `Ger`.`Nombre`            AS `Nombre_Gerencia`,

        /* Nivel 2: Subdirección (Padre) */
        `Ger`.`Fk_Id_CatSubDirec` AS `Id_Subdireccion`,
        `Sub`.`Clave`             AS `Clave_Subdireccion`,
        `Sub`.`Nombre`            AS `Nombre_Subdireccion`,

        /* Nivel 3: Dirección Corporativa (Abuelo) */
        `Sub`.`Fk_Id_CatDirecc`   AS `Id_Direccion`,
        `Dir`.`Clave`             AS `Clave_Direccion`,
        `Dir`.`Nombre`            AS `Nombre_Direccion`,

        /* =================================================================================
           CONJUNTO 9: AUDITORÍA
           ================================================================================= */
           
		`IP`.`Nivel`,
        `IP`.`Clasificacion`,
		`U`.`Activo` AS `Estatus_Usuario`,
        `IP`.`updated_at`         AS `Ultima_Modificacion_Perfil`

    FROM `Usuarios` `U`

    /* 1. NÚCLEO: Info Personal */
    LEFT JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* 2. ORGANIZACIÓN: Gerencia -> Subdirección -> Dirección */
    LEFT JOIN `Cat_Gerencias_Activos` `Ger` ON `IP`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    LEFT JOIN `Cat_Subdirecciones` `Sub`    ON `Ger`.`Fk_Id_CatSubDirec` = `Sub`.`Id_CatSubDirec`
    LEFT JOIN `Cat_Direcciones` `Dir`       ON `Sub`.`Fk_Id_CatDirecc` = `Dir`.`Id_CatDirecc`

    /* 3. UBICACIÓN CT: CT -> Mun -> Edo -> Pais (Vital para cascada) */
    LEFT JOIN `Cat_Centros_Trabajo` `CT` ON `IP`.`Fk_Id_CatCT` = `CT`.`Id_CatCT`
    LEFT JOIN `Municipio` `MunCT`        ON `CT`.`Fk_Id_Municipio_CatCT` = `MunCT`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoCT`           ON `MunCT`.`Fk_Id_Estado` = `EdoCT`.`Id_Estado`
    LEFT JOIN `Pais` `PaisCT`            ON `EdoCT`.`Fk_Id_Pais` = `PaisCT`.`Id_Pais`

    /* 4. UBICACIÓN DEPTO: Depto -> Mun -> Edo -> Pais (Vital para cascada) */
    LEFT JOIN `Cat_Departamentos` `Dep` ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`
    LEFT JOIN `Municipio` `MunDep`      ON `Dep`.`Fk_Id_Municipio_CatDep` = `MunDep`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoDep`         ON `MunDep`.`Fk_Id_Estado` = `EdoDep`.`Id_Estado`
    LEFT JOIN `Pais` `PaisDep`          ON `EdoDep`.`Fk_Id_Pais` = `PaisDep`.`Id_Pais`

    /* 5. OTROS CATÁLOGOS */
    LEFT JOIN `Cat_Regimenes_Trabajo` `Reg` ON `IP`.`Fk_Id_CatRegimen` = `Reg`.`Id_CatRegimen`
    LEFT JOIN `Cat_Regiones_Trabajo` `Region` ON `IP`.`Fk_Id_CatRegion` = `Region`.`Id_CatRegion`
    LEFT JOIN `Cat_Puestos_Trabajo` `Puesto` ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`

    WHERE `U`.`Id_Usuario` = _Id_Usuario_Sesion
    LIMIT 1;

END$$

DELIMITER ;