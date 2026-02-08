/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarPerfilPropio]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE / Gemini
   FECHA: 2026
   VERSIÓN: 1.7 (ENTITY-CENTRIC & FULL DOCUMENTATION)

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar la "Hoja de Vida Digital" completa del usuario logueado para dos fines:
     A) VISUALIZACIÓN (READ-ONLY): Mostrar al usuario sus datos actuales, ubicación y adscripción
        con nombres claros (no solo IDs) y direcciones físicas.
     B) EDICIÓN (HYDRATION): Proveer todos los IDs necesarios (Foreign Keys) para pre-cargar 
        los formularios de edición, incluyendo la lógica compleja de selectores en cascada.

   2. FILOSOFÍA DE DISEÑO: AGRUPACIÓN POR ENTIDAD (ENTITY-CENTRIC)
   ---------------------------------------------------------------
   La proyección de columnas (SELECT) no está ordenada por tipo de dato, sino agrupada por 
   OBJETO DE NEGOCIO. 
   Ejemplo: El bloque "Centro de Trabajo" contiene contiguamente su ID, Nombre, Dirección 
   y toda su cadena geográfica (Municipio -> Estado -> País).
   
   Beneficio: Facilita el mapeo en el Frontend (Angular/React/Vue) al permitir instanciar 
   objetos completos sin saltar líneas.

   3. RETO TÉCNICO: RECONSTRUCCIÓN JERÁRQUICA (CASCADING DROPDOWNS)
   ----------------------------------------------------------------
   El usuario solo tiene guardado el ID del hijo (ej: Id_Gerencia o Id_CentroTrabajo).
   Sin embargo, los formularios de edición requieren seleccionar primero al abuelo y al padre.
   
   SOLUCIÓN: Este SP realiza "JOINS Ascendentes" para reconstruir y devolver:
     - Geografía: [Municipio] -> [Estado] -> [País]
     - Organización: [Gerencia] -> [Subdirección] -> [Dirección]
   
   Esto permite que la UI "autoseleccione" los combos padres automáticamente.

   4. ESTRATEGIA DE INTEGRIDAD (ANTI-FRAGILITY)
   --------------------------------------------
   Se utilizan exclusivamente `LEFT JOIN`.
   Razón: Si un catálogo es eliminado físicamente o hay inconsistencia en datos legados,
   el perfil del usuario NO debe romperse. La consulta devolverá los datos parciales disponibles,
   permitiendo al usuario entrar y corregir la información faltante.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarPerfilPropio`$$
CREATE PROCEDURE `SP_ConsultarPerfilPropio`(
    IN _Id_Usuario_Sesion INT -- Token o ID del usuario autenticado
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Evitar desperdicio de ciclos de CPU si el parámetro es nulo o inválido.
       ======================================================================================== */
    IF _Id_Usuario_Sesion IS NULL OR _Id_Usuario_Sesion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de sesión inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el usuario exista antes de intentar ensamblar su perfil complejo.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Sesion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA MAESTRA (PROYECCIÓN DE DATOS)
       ======================================================================================== */
    SELECT 
        /* ---------------------------------------------------------------------------------
           CONJUNTO 1: IDENTIDAD Y ACCESO (Tabla Usuarios)
           Datos inmutables o de sistema asociados a la cuenta.
           --------------------------------------------------------------------------------- */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,
        `U`.`Email`,
        -- `U`.`Foto_Perfil_Url`, (Descomentar si se implementa módulo de imágenes)

        /* ---------------------------------------------------------------------------------
           CONJUNTO 2: DATOS PERSONALES Y HUMANOS (Tabla Info_Personal)
           Información demográfica y administrativa del empleado.
           --------------------------------------------------------------------------------- */
        `IP`.`Id_InfoPersonal`,
        
        /* Helper SQL: Concatenación para Header de Perfil. 
           Usa IFNULL para evitar que un campo vacío anule todo el string. */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 3: RÉGIMEN CONTRACTUAL
           Vinculación legal del empleado con la empresa.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`, -- Binding para [(ngModel)]
        -- `Reg`.`Codigo`            AS `Codigo_Regimen`,
        -- `Reg`.`Nombre`            AS `Nombre_Regimen`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 4: PUESTO DE TRABAJO
           Rol operativo o administrativo asignado.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,  -- Binding para [(ngModel)]
        -- `Puesto`.`Codigo`         AS `Codigo_Puesto`,
        -- `Puesto`.`Nombre`         AS `Nombre_Puesto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 5: CENTRO DE TRABAJO (CT) + GEOGRAFÍA COMPLETA
           Este bloque resuelve la ubicación física del empleado.
           CRÍTICO: Incluye la reconstrucción CT -> Mun -> Edo -> Pais para la cascada.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatCT`        AS `Id_CentroTrabajo`, -- Binding principal
        -- `CT`.`Codigo`             AS `Codigo_CentroTrabajo`,
        -- `CT`.`Nombre`             AS `Nombre_CentroTrabajo`,
        -- `CT`.`Direccion_Fisica`   AS `Direccion_Fisica_CT`,
        
        /* Reconstrucción Geográfica Ascendente (Child -> Parent -> Grandparent) */
        `CT`.`Fk_Id_Municipio_CatCT` AS `Id_Municipio_CT`,
        -- `MunCT`.`Codigo`          AS `Codigo_Municipio_CT`,
        -- `MunCT`.`Nombre`          AS `Nombre_Municipio_CT`,
        
        `EdoCT`.`Id_Estado`       AS `Id_Estado_CT`, -- Necesario para pre-cargar combo Estado
        -- `EdoCT`.`Codigo`          AS `Codigo_Estado_CT`,
        -- `EdoCT`.`Nombre`       AS `Nombre_Estado_CT`,
        
        `PaisCT`.`Id_Pais`        AS `Id_Pais_CT`,   -- Necesario para pre-cargar combo País
        -- `PaisCT`.`Codigo`         AS `Codigo_Pais_CT`,
        -- `PaisCT`.`Nombre`      AS `Nombre_Pais_CT`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 6: DEPARTAMENTO + GEOGRAFÍA COMPLETA
           Ubicación administrativa del empleado. Sigue la misma lógica de cascada que el CT.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatDep`       AS `Id_Departamento`, -- Binding principal
        -- `Dep`.`Codigo`            AS `Codigo_Departamento`,
        -- `Dep`.`Nombre`            AS `Nombre_Departamento`,
        -- `Dep`.`Direccion_Fisica`  AS `Direccion_Fisica_Depto`,
        
        /* Reconstrucción Geográfica Ascendente */
        `Dep`.`Fk_Id_Municipio_CatDep` AS `Id_Municipio_Depto`,
        -- `MunDep`.`Codigo`         AS `Codigo_Municipio_Depto`,
        -- `MunDep`.`Nombre`         AS `Nombre_Municipio_Depto`,
        
        `EdoDep`.`Id_Estado`      AS `Id_Estado_Depto`,
        -- `EdoDep`.`Codigo`         AS `Codigo_Estado_Depto`,
        -- `EdoDep`.`Nombre`      AS `Nombre_Estado_Depto`,
        
        `PaisDep`.`Id_Pais`       AS `Id_Pais_Depto`,
        -- `PaisDep`.`Codigo`        AS `Codigo_Pais_Depto`,
        -- `PaisDep`.`Nombre`     AS `Nombre_Pais_Depto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 7: REGIÓN OPERATIVA
           Zona geográfica macro de operación.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegion`    AS `Id_Region`,
        -- `Region`.`Codigo`         AS `Codigo_Region`,
        -- `Region`.`Nombre`         AS `Nombre_Region`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 8: JERARQUÍA ORGANIZACIONAL (ORGANIGRAMA)
           Reconstrucción de la cadena de mando: Gerencia -> Subdirección -> Dirección.
           Vital para que los selectores dependientes se llenen correctamente.
           --------------------------------------------------------------------------------- */
        /* Nivel 1: Gerencia (Nodo Hoja - Asignación Directa) */
        `IP`.`Fk_Id_CatGeren`     AS `Id_Gerencia`,
        -- `Ger`.`Clave`             AS `Clave_Gerencia`,
        -- `Ger`.`Nombre`            AS `Nombre_Gerencia`,

        /* Nivel 2: Subdirección (Nodo Padre - Derivado) */
         `Ger`.`Fk_Id_CatSubDirec` AS `Id_Subdireccion`,
        -- `Sub`.`Clave`             AS `Clave_Subdireccion`,
        -- `Sub`.`Nombre`            AS `Nombre_Subdireccion`,

        /* Nivel 3: Dirección Corporativa (Nodo Abuelo - Derivado) */
        `Sub`.`Fk_Id_CatDirecc`   AS `Id_Direccion`,
        -- `Dir`.`Clave`             AS `Clave_Direccion`,
        -- `Dir`.`Nombre`            AS `Nombre_Direccion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 9: AUDITORÍA Y METADATOS
           Información de control y clasificación salarial/administrativa.
           --------------------------------------------------------------------------------- */
        `IP`.`Nivel`,
        `IP`.`Clasificacion`,
        `U`.`Activo`              AS `Estatus_Usuario`,
        `IP`.`updated_at`         AS `Ultima_Modificacion_Perfil`

    FROM `Usuarios` `U`

    /* =================================================================================
       ESTRATEGIA DE UNIONES (JOINS)
       Se usan LEFT JOIN para garantizar que el perfil se cargue incluso si faltan datos
       o si existen inconsistencias en catálogos antiguos.
       ================================================================================= */

    /* 1. NÚCLEO: Enlace con la tabla extendida de información personal */
    LEFT JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* 2. ORGANIZACIÓN: Reconstrucción ascendente del organigrama */
    LEFT JOIN `Cat_Gerencias_Activos` `Ger` ON `IP`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    LEFT JOIN `Cat_Subdirecciones` `Sub`    ON `Ger`.`Fk_Id_CatSubDirec` = `Sub`.`Id_CatSubDirec`
    LEFT JOIN `Cat_Direcciones` `Dir`       ON `Sub`.`Fk_Id_CatDirecc` = `Dir`.`Id_CatDirecc`

    /* 3. UBICACIÓN CT: Cadena geográfica completa para el Centro de Trabajo */
    LEFT JOIN `Cat_Centros_Trabajo` `CT` ON `IP`.`Fk_Id_CatCT` = `CT`.`Id_CatCT`
    LEFT JOIN `Municipio` `MunCT`        ON `CT`.`Fk_Id_Municipio_CatCT` = `MunCT`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoCT`           ON `MunCT`.`Fk_Id_Estado` = `EdoCT`.`Id_Estado`
    LEFT JOIN `Pais` `PaisCT`            ON `EdoCT`.`Fk_Id_Pais` = `PaisCT`.`Id_Pais`

    /* 4. UBICACIÓN DEPTO: Cadena geográfica completa para el Departamento */
    LEFT JOIN `Cat_Departamentos` `Dep` ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`
    LEFT JOIN `Municipio` `MunDep`      ON `Dep`.`Fk_Id_Municipio_CatDep` = `MunDep`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoDep`         ON `MunDep`.`Fk_Id_Estado` = `EdoDep`.`Id_Estado`
    LEFT JOIN `Pais` `PaisDep`          ON `EdoDep`.`Fk_Id_Pais` = `PaisDep`.`Id_Pais`

    /* 5. OTROS CATÁLOGOS SIMPLES */
    LEFT JOIN `Cat_Regimenes_Trabajo` `Reg`   ON `IP`.`Fk_Id_CatRegimen` = `Reg`.`Id_CatRegimen`
    LEFT JOIN `Cat_Regiones_Trabajo` `Region` ON `IP`.`Fk_Id_CatRegion` = `Region`.`Id_CatRegion`
    LEFT JOIN `Cat_Puestos_Trabajo` `Puesto`  ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`

    /* =================================================================================
       FILTRO FINAL
       ================================================================================= */
    WHERE `U`.`Id_Usuario` = _Id_Usuario_Sesion
    LIMIT 1;

END$$

DELIMITER ;