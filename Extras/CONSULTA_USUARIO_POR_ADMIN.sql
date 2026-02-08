/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarUsuarioPorAdmin]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE / Gemini
   FECHA: 2026
   VERSIÓN: 1.3 (FULL AUDIT & HYDRATION STRATEGY - GOLD STANDARD DOCS)

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer al Administrador de Sistema una "Radiografía Técnica Completa" de cualquier usuario
   registrado en la base de datos, independientemente de su estado actual (Activo/Inactivo).

   Este procedimiento actúa como el backend para dos interfaces críticas:
     A) VISOR DE DETALLE (MODAL DE AUDITORÍA): Donde se inspecciona quién es el usuario,
        quién lo registró, cuándo y qué permisos tiene.
     B) FORMULARIO DE EDICIÓN AVANZADA (UPDATE): Donde el Admin puede corregir datos,
        reasignar roles, cambiar de adscripción o bloquear el acceso.

   2. DIFERENCIAS CRÍTICAS VS "PERFIL PROPIO" (SCOPE)
   --------------------------------------------------
   Mientras que el perfil de usuario es de "Solo Lectura" para ciertos campos, esta vista:
     - EXPONE LA SEGURIDAD: Devuelve el `Id_Rol` y `Activo` para permitir su modificación.
     - ROMPE EL SILENCIO: No filtra por `Activo = 1`. Permite gestionar usuarios "Baneados"
       o dados de baja lógica para su eventual reactivación.
     - TRAZABILIDAD TOTAL: Revela la identidad de los autores de los cambios (Created_By/Updated_By),
       resolviendo sus IDs a Nombres Reales mediante JOINs reflexivos.

   3. ARQUITECTURA DE DATOS: "LEAN HYDRATION" (CARGA LIGERA)
   ---------------------------------------------------------
   Para optimizar el rendimiento del Frontend (Angular/React/Vue), este SP no devuelve los
   catálogos completos (listas de opciones), sino los punteros (Foreign Keys) necesarios para
   que los componentes visuales se "auto-configuren":
   
     - Estrategia de Binding: Se retornan IDs (ej: `Id_Puesto`) para que el Dropdown seleccione
       automáticamente la opción correcta.
     - Estrategia de Cascada: Se retornan los IDs de los Ancestros (Municipio -> Estado -> País)
       para disparar la carga de listas dependientes sin intervención del usuario.

   4. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   -----------------------------------------
   El resultset se estructura en 10 bloques lógicos que mapean directamente las secciones
   visuales del formulario de Administración:
     [1] Identidad Digital (Ficha/Email)
     [2] Seguridad (Rol/Estatus)
     [3] Identidad Humana (Nombres)
     [4] Adscripción Simple (Puesto)
     [5] Ubicación Física (Centro de Trabajo + Geografía)
     [6] Ubicación Administrativa (Departamento + Geografía)
     [7] Región Operativa
     [8] Jerarquía de Mando (Organigrama)
     [9] Metadatos (Nivel/Clasificación)
     [10] Auditoría (Fechas y Responsables)
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarUsuarioPorAdmin`$$

CREATE PROCEDURE `SP_ConsultarUsuarioPorAdmin`(
    IN _Id_Usuario_Objetivo INT -- Identificador único del usuario a inspeccionar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido cumpla con los requisitos mínimos
       antes de intentar cualquier operación de lectura. 
       ======================================================================================== */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de usuario objetivo inválido (Debe ser entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE DISEÑO: Aquí NO validamos `Activo = 1`. El Admin tiene permisos de "Dios"
       para ver registros eliminados lógicamente.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Objetivo) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe en la base de datos.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA MAESTRA (FULL DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo, reconstruyendo jerarquías y auditoría.
       ======================================================================================== */
    SELECT 
        /* ---------------------------------------------------------------------------------
           CONJUNTO 1: IDENTIDAD Y CREDENCIALES
           Datos fundamentales de la cuenta. Inmutables para el usuario, editables por Admin.
           --------------------------------------------------------------------------------- */
        `U`.`Id_Usuario`,
        `U`.`Ficha`,
        `U`.`Email`,
        `U`.`Foto_Perfil_Url`, -- Recurso multimedia (Avatar)

        /* ---------------------------------------------------------------------------------
           CONJUNTO 2: DATOS PERSONALES (INFO HUMANOS)
           Información demográfica proveniente de la tabla satélite `Info_Personal`.
           --------------------------------------------------------------------------------- */
        `IP`.`Id_InfoPersonal`,
        
        /* Helper Visual: Nombre Completo Concatenado.
           Útil para mostrar en el título del modal ("Editando a: JUAN PÉREZ") sin procesar en JS. */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,''), ' ', IFNULL(`IP`.`Apellido_Materno`,'')) AS `Nombre_Completo_Concatenado`,
        
        /* Datos atómicos para edición en inputs separados */
        `IP`.`Nombre`,
        `IP`.`Apellido_Paterno`,
        `IP`.`Apellido_Materno`,
        `IP`.`Fecha_Nacimiento`,
        `IP`.`Fecha_Ingreso`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 3: ADSCRIPCIÓN SIMPLE (SOLO IDs)
           Estos campos no tienen dependencias complejas. El Frontend usará el ID para
           seleccionar el valor correcto en el Dropdown correspondiente.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegimen`   AS `Id_Regimen`,
        `IP`.`Fk_Id_CatPuesto`    AS `Id_Puesto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 4: CENTRO DE TRABAJO + CASCADA GEOGRÁFICA (REVERSE LOOKUP)
           El reto aquí es que `Info_Personal` solo guarda el ID del Centro de Trabajo.
           Para que el Frontend pueda mostrar los selectores de País, Estado y Municipio
           correctamente pre-llenados, debemos "subir" por la jerarquía y devolver esos IDs.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatCT`            AS `Id_CentroTrabajo`, -- Valor final seleccionado
        
        /* Triggers de Cascada Geográfica (Ancestros) */
        `CT`.`Fk_Id_Municipio_CatCT`  AS `Id_Municipio_CT`,
        `EdoCT`.`Id_Estado`           AS `Id_Estado_CT`,
        `PaisCT`.`Id_Pais`            AS `Id_Pais_CT`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 5: DEPARTAMENTO + CASCADA GEOGRÁFICA
           Misma lógica de reconstrucción inversa que el Centro de Trabajo.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatDep`           AS `Id_Departamento`, -- Valor final seleccionado
        
        /* Triggers de Cascada Geográfica (Ancestros) */
        `Dep`.`Fk_Id_Municipio_CatDep` AS `Id_Municipio_Depto`,
        `EdoDep`.`Id_Estado`           AS `Id_Estado_Depto`,
        `PaisDep`.`Id_Pais`            AS `Id_Pais_Depto`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 6: REGIÓN OPERATIVA
           Ubicada visualmente tras el Departamento según el flujo de UI definido.
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatRegion`        AS `Id_Region`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 7: JERARQUÍA ORGANIZACIONAL (ORGANIGRAMA)
           Reconstrucción de la cadena de mando administrativa.
           Ruta: Gerencia (Hijo) -> Subdirección (Padre) -> Dirección (Abuelo).
           --------------------------------------------------------------------------------- */
        `IP`.`Fk_Id_CatGeren`         AS `Id_Gerencia`,      -- Valor final seleccionado
        
        /* Triggers de Cascada Organizacional (Ancestros) */
        `Ger`.`Fk_Id_CatSubDirec`     AS `Id_Subdireccion`,
        `Sub`.`Fk_Id_CatDirecc`       AS `Id_Direccion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 8: METADATOS ADMINISTRATIVOS
           Datos tabulares sin catálogo relacional fuerte.
           --------------------------------------------------------------------------------- */
        `IP`.`Nivel`,
        `IP`.`Clasificacion`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 9: TRAZABILIDAD Y AUDITORÍA (RICH AUDIT TRAIL)
           Aquí resolvemos la pregunta: "¿Quién hizo esto?".
           En lugar de devolver IDs numéricos ("Creado por: 45"), hacemos JOINs reflexivos
           para devolver el Nombre Real del responsable.
           --------------------------------------------------------------------------------- */
        /* DATOS DE CREACIÓN */
        `U`.`created_at`              AS `Fecha_Registro`,
        /* Si Created_By es NULL (migración), mostramos 'System', si no, el nombre concatenado */
        CONCAT(IFNULL(`Info_Crt`.`Nombre`,'System'), ' ', IFNULL(`Info_Crt`.`Apellido_Paterno`,'')) AS `Creado_Por_Nombre`,
        
        /* DATOS DE ACTUALIZACIÓN */
        `U`.`updated_at`              AS `Fecha_Ultima_Modificacion`,
        CONCAT(IFNULL(`Info_Upd`.`Nombre`,''), ' ', IFNULL(`Info_Upd`.`Apellido_Paterno`,''))       AS `Actualizado_Por_Nombre`,

        /* ---------------------------------------------------------------------------------
           CONJUNTO 10: SEGURIDAD Y CONTROL (EXCLUSIVO ADMIN)
           Ubicados al final del JSON para coincidir con la sección de "Acciones Críticas"
           (Footer) del formulario de edición.
           --------------------------------------------------------------------------------- */
        `U`.`Fk_Rol`                  AS `Id_Rol`,           -- Binding para Dropdown de Roles
        `U`.`Activo`                  AS `Estatus_Usuario`   -- Binding para Switch Activo/Inactivo

    FROM `Usuarios` `U`

    /* =================================================================================
       ESTRATEGIA DE UNIONES (JOINS)
       Se utiliza `LEFT JOIN` masivamente.
       
       JUSTIFICACIÓN DE INTEGRIDAD:
       Priorizamos la "Disponibilidad de Datos" sobre la "Consistencia Estricta".
       Si un usuario tiene un ID de Departamento que fue eliminado físicamente (catálogo roto),
       un INNER JOIN ocultaría al usuario completo.
       Con LEFT JOIN, mostramos al usuario con el campo departamento vacío, permitiendo
       al Administrador detectar el error y corregirlo (Self-Healing).
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

    /* 5. AUDITORÍA (JOINS REFLEXIVOS / SELF-JOINS)
       Objetivo: Obtener el nombre legible de los responsables de creación/edición.
       Mecánica: 
         a) `U` -> `Usuarios` (Creador) -> `Info_Personal` (Nombre Creador)
         b) `U` -> `Usuarios` (Editor) -> `Info_Personal` (Nombre Editor)
       Se usan alias distintos (`Info_Crt`, `Info_Upd`) para no colisionar con el `IP` principal. */
       
    /* 5.1 Resolver Identidad del Creador */
    LEFT JOIN `Usuarios` `User_Crt`       ON `U`.`Fk_Usuario_Created_By` = `User_Crt`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `Info_Crt`  ON `User_Crt`.`Fk_Id_InfoPersonal` = `Info_Crt`.`Id_InfoPersonal`

    /* 5.2 Resolver Identidad del Editor (Última modificación) */
    LEFT JOIN `Usuarios` `User_Upd`       ON `U`.`Fk_Usuario_Updated_By` = `User_Upd`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `Info_Upd`  ON `User_Upd`.`Fk_Id_InfoPersonal` = `Info_Upd`.`Id_InfoPersonal`

    /* =================================================================================
       FILTRO FINAL
       ================================================================================= */
    WHERE `U`.`Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1; /* Buena práctica: Detener el escaneo tras el primer hallazgo */

END$$

DELIMITER ;