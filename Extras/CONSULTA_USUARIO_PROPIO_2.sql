/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarPerfilPropio]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE / Gemini
   FECHA: 2026
   VERSIÓN: 2.0 (LEAN HYDRATION STRATEGY & FULL DOCUMENTATION)

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Recuperar el "Expediente Digital" del usuario autenticado, optimizado específicamente para
   la hidratación (pre-llenado) de formularios reactivos en el Frontend (Angular/React/Vue).

   A diferencia de un reporte visual, este SP está diseñado para ser consumido por componentes
   de UI tipo "Smart Form", donde los catálogos ya están cargados en memoria y solo se requiere
   el ID (Foreign Key) para realizar el "Data Binding" automático.

   2. FILOSOFÍA DE DISEÑO: "LEAN PAYLOAD" (CARGA LIGERA)
   -----------------------------------------------------
   - Principio: "No envíes lo que el cliente ya sabe".
   - Implementación: Se eliminan campos redundantes como `Nombre_Regimen` o `Codigo_Puesto`,
     ya que el Frontend posee esos textos en sus listas desplegables.
   - Beneficio: Reducción drástica del tamaño del JSON de respuesta y menor latencia de red.

   3. ARQUITECTURA DE DATOS (ENTITY-CENTRIC GROUPING)
   --------------------------------------------------
   La proyección de columnas (SELECT) se organiza agrupando lógicamente los datos por Entidad
   de Negocio (Usuario, InfoPersonal, CentroTrabajo, Departamento), facilitando la lectura
   y el mantenimiento del código.

   4. RETO TÉCNICO: RECONSTRUCCIÓN DE CASCADAS (REVERSE LOOKUP)
   ------------------------------------------------------------
   El modelo de datos normalizado solo almacena el nodo hoja (ej: `Id_CentroTrabajo`).
   Sin embargo, la UI requiere seleccionar primero los nodos padres (País -> Estado -> Municipio).
   
   SOLUCIÓN: Este SP realiza "JOINS Ascendentes" para recuperar los IDs de toda la cadena
   jerárquica (Ancestros), permitiendo que el Frontend dispare la carga de listas dependientes
   automáticamente al recibir los datos.

   5. ESTRATEGIA DE INTEGRIDAD (ANTI-FRAGILITY)
   --------------------------------------------
   Se utilizan exclusivamente `LEFT JOIN`.
   Razón: Garantizar que el perfil sea accesible incluso si existen inconsistencias referenciales
   (ej: un Centro de Trabajo antiguo eliminado físicamente). Esto permite al usuario entrar
   al formulario y corregir la información faltante ("Self-Healing Data").
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarPerfilPropio`$$
CREATE PROCEDURE `SP_ConsultarPerfilPropio`(
    IN _Id_Usuario_Sesion INT -- Token de sesión o ID primario del usuario
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Evitar ejecución de querys costosos si el parámetro es inválido.
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
       BLOQUE 3: CONSULTA MAESTRA (LEAN PROJECTION)
       ======================================================================================== */
    SELECT 
        /* ---------------------------------------------------------------------------------
           CONJUNTO 1: IDENTIDAD Y ACCESO (Tabla Usuarios)
           Datos crudos para visualización estática en el encabezado del perfil.
           --------------------------------------------------------------------------------- */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,
        `U`.`Email`,
        `U`.`Foto_Perfil_Url`,-- (Habilitar si se requiere mostrar el avatar)

        /* ---------------------------------------------------------------------------------
           CONJUNTO 2: DATOS PERSONALES Y HUMANOS (Tabla Info_Personal)
           Datos editables que se bindean a inputs de texto y fecha.
           --------------------------------------------------------------------------------- */
        `IP`.`Id_InfoPersonal`,
        
        /* Helper Visual: Concatenación para título de página (Solo lectura) */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 3: ADSCRIPCIÓN SIMPLE (SOLO IDs)
           Estos campos alimentan Dropdowns independientes (sin dependencias).
           El Frontend usará el ID para seleccionar el objeto correcto de su catálogo en memoria.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`,
        -- `Reg`.`Codigo`            AS `Codigo_Regimen`,
        -- `Reg`.`Nombre`            AS `Nombre_Regimen`,
        
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,
        -- `Puesto`.`Codigo`         AS `Codigo_Puesto`,
        -- `Puesto`.`Nombre`         AS `Nombre_Puesto`,
        
        /* ---------------------------------------------------------------------------------
           CONJUNTO 4: CENTRO DE TRABAJO (CT) + TRIGGERS DE CASCADA
           Objetivo: Permitir la reconstrucción automática de los selectores geográficos.
           Lógica: Recuperamos los ancestros (Mun -> Edo -> Pais) para que la UI sepa qué cargar.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatCT`            AS `Id_CentroTrabajo`, -- Valor seleccionado
        -- `CT`.`Codigo`             AS `Codigo_CentroTrabajo`,
        -- `CT`.`Nombre`             AS `Nombre_CentroTrabajo`,
        -- `CT`.`Direccion_Fisica`   AS `Direccion_Fisica_CT`,
        
        /* Ancestros Geográficos del CT */
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
           CONJUNTO 5: DEPARTAMENTO + TRIGGERS DE CASCADA
           Misma lógica que el CT: ID del Departamento + IDs de la ruta geográfica.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatDep`           AS `Id_Departamento`, -- Valor seleccionado
        -- `Dep`.`Codigo`            AS `Codigo_Departamento`,
        -- `Dep`.`Nombre`            AS `Nombre_Departamento`,
        -- `Dep`.`Direccion_Fisica`  AS `Direccion_Fisica_Depto`,
        
        /* Ancestros Geográficos del Departamento */
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
           CONJUNTO 5.5: REGIÓN OPERATIVA
           Zona geográfica macro de operación.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegion`    AS `Id_Region`,
        -- `Region`.`Codigo`         AS `Codigo_Region`,
        -- `Region`.`Nombre`         AS `Nombre_Region`,
        
        /* ---------------------------------------------------------------------------------
           CONJUNTO 6: JERARQUÍA ORGANIZACIONAL (ORGANIGRAMA)
           Reconstrucción de la cadena de mando para selectores dependientes.
           Ruta: Gerencia (Hijo) -> Subdirección (Padre) -> Dirección (Abuelo).
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatGeren`         AS `Id_Gerencia`,      -- Valor seleccionado
        
        /* Ancestros Organizacionales */
        /* Nivel 1: Gerencia (Nodo Hoja - Asignación Directa) */
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
           CONJUNTO 7: METADATOS Y AUDITORÍA
           Información de control interno y clasificación.
           --------------------------------------------------------------------------------- */
        `IP`.`Nivel`,
        `IP`.`Clasificacion`,
        `U`.`Activo`              AS `Estatus_Usuario`,
        `IP`.`updated_at`         AS `Ultima_Modificacion_Perfil`

    FROM `Usuarios` `U`

    /* =================================================================================
       ESTRATEGIA DE UNIONES (JOINS)
       Se prioriza la robustez (LEFT JOIN) sobre la estrictez (INNER JOIN).
       ================================================================================= */

    /* 1. NÚCLEO: Enlace con la tabla extendida de información personal */
    LEFT JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* 2. JERARQUÍA ORGANIZACIONAL: Recuperación de IDs Padres para Cascada */
    LEFT JOIN `Cat_Gerencias_Activos` `Ger` ON `IP`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    LEFT JOIN `Cat_Subdirecciones` `Sub`    ON `Ger`.`Fk_Id_CatSubDirec` = `Sub`.`Id_CatSubDirec`
	LEFT JOIN `Cat_Direcciones` `Dir`       ON `Sub`.`Fk_Id_CatDirecc` = `Dir`.`Id_CatDirecc`
    
    /* 3. GEOGRAFÍA CT: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Centros_Trabajo` `CT` ON `IP`.`Fk_Id_CatCT` = `CT`.`Id_CatCT`
    LEFT JOIN `Municipio` `MunCT`        ON `CT`.`Fk_Id_Municipio_CatCT` = `MunCT`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoCT`           ON `MunCT`.`Fk_Id_Estado` = `EdoCT`.`Id_Estado`
    LEFT JOIN `Pais` `PaisCT`            ON `EdoCT`.`Fk_Id_Pais` = `PaisCT`.`Id_Pais`

    /* 4. GEOGRAFÍA DEPTO: Recuperación de IDs Ancestros para Cascada */
    LEFT JOIN `Cat_Departamentos` `Dep` ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`
    LEFT JOIN `Municipio` `MunDep`      ON `Dep`.`Fk_Id_Municipio_CatDep` = `MunDep`.`Id_Municipio`
    LEFT JOIN `Estado` `EdoDep`         ON `MunDep`.`Fk_Id_Estado` = `EdoDep`.`Id_Estado`
    LEFT JOIN `Pais` `PaisDep`          ON `EdoDep`.`Fk_Id_Pais` = `PaisDep`.`Id_Pais`

    /* NOTA DE OPTIMIZACIÓN: 
       Se han eliminado los JOINs a las tablas `Cat_Puestos_Trabajo`, `Cat_Regimenes_Trabajo`
       y `Cat_Regiones_Trabajo` ya que, bajo la estrategia "Lean Payload", no se requieren
       sus campos descriptivos (Nombre, Código), bastando con el ID presente en `Info_Personal`. */

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