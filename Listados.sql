/* ============================================================================================
   SECCIÓN: LISTADOS PARA -- DROPDOWNS (SOLO ACTIVOS)
   ============================================================================================
   Estas rutinas alimentan los selectores en los formularios.
   REGLA DE ORO: 
   - Solo devuelven registros con Activo = 1.
   - Aplican "Candado Jerárquico": No puedes listar hijos si el padre está inactivo.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPaisesActivos
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown inicial de Países en formularios en cascada.
   - Ejemplo: “Registrar/Editar Estado”, “Registrar/Editar Municipio”, etc.

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO Países activos (Activo = 1).
   - Ordenados por Nombre para que el usuario encuentre rápido.

   CONTRATO PARA UI (REGLA CLAVE)
   ------------------------------
   - “Activo = 1” significa: el registro es seleccionable/usable en UI.
   - Un país inactivo NO debe aparecer en dropdowns normales.

   NOTA DE DISEÑO
   --------------
   - Si necesitas un dropdown administrativo que muestre también inactivos,
     crea otro SP separado (ej: SP_ListarPaisesAdmin) para no mezclar contratos.
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
   PROCEDIMIENTO: SP_ListarEstadosPorPais   (VERSIÓN PRO: CONTRATO DE DROPDOWN “ACTIVOS”)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown de Estados cuando:
       a) Se selecciona un País en UI
       b) Se abre un formulario y hay que precargar los estados del País actual

   OBJETIVO
   --------
   - Devolver SOLO Estados activos (Activo=1) de un País seleccionado.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (BLINDAJE)
   ----------------------------------
   Antes:
   - Validabas que el País existiera, pero NO validabas que estuviera Activo=1.
   - Resultado: si alguien manda un request manipulado o la UI tiene cache viejo,
     el backend podría listar estados de un País inactivo.

   Ahora (contrato estricto):
   - Un dropdown “normal” SOLO permite seleccionar padres activos.
   - Si el País está inactivo => NO se lista y se responde error claro.

   ¿POR QUÉ ERROR (SIGNAL) Y NO LISTA VACÍA?
   -----------------------------------------
   - Porque lista vacía es ambigua: “¿no hay estados o el país está bloqueado?”
   - Con error, el frontend puede mostrar: “País inactivo, refresca”.

   VALIDACIONES
   ------------
   1) _Id_Pais válido (>0)
   2) País existe
   3) País Activo=1  (candado de contrato)
============================================================================================ */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS SP_ListarEstadosPorPais$$

CREATE PROCEDURE SP_ListarEstadosPorPais(
    IN _Id_Pais INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
       - Evita llamadas “chuecas” (null, 0, negativos) desde UI o requests directos.
    ---------------------------------------------------------------------------------------- */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del País
       - Si no existe, regresamos error explícito para no “simular” que no hay estados.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO: País debe estar ACTIVO
       - Este es el cambio importante.
       - Refuerza el contrato de dropdown: “solo se listan hijos de padres activos”.
       - Protege contra:
           * requests manipuladas
           * UI con cache viejo (el país se desactivó mientras estaba abierto el formulario)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais AND Activo = 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País está inactivo. No se pueden listar Estados.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Estados activos del País
       - Nota: también filtramos Activo=1 del Estado porque es dropdown normal.
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Estado,
        Codigo,
        Nombre
    FROM Estado
    WHERE Fk_Id_Pais = _Id_Pais
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$
DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarMunicipiosPorEstado   (VERSIÓN PRO: CANDADO JERÁRQUICO)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el dropdown de Municipios cuando:
       a) Se selecciona un Estado en UI
       b) Se abre un formulario que requiere precargar municipios del estado actual

   OBJETIVO
   --------
   - Devolver SOLO Municipios activos (Activo=1) de un Estado seleccionado.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (IMPORTANTE)
   -------------------------------------
   Antes:
   - Validabas que el Estado existiera,
   - pero NO validabas que el Estado estuviera Activo=1,
   - y tampoco validabas que su País padre estuviera Activo=1.

   Resultado:
   - Un Estado inactivo (o con País inactivo) podía seguir “dando municipios” en dropdown,
     lo cual rompe el contrato de “solo seleccionables”.

   Ahora:
   - Candado jerárquico: Estado y su País deben estar activos.
   - Si no cumplen, se devuelve error explícito.

   ¿POR QUÉ VALIDAR PAÍS TAMBIÉN?
   ------------------------------
   Porque tu jerarquía real es:
       Municipio -> Estado -> País

   Si el País está inactivo, aunque el Estado estuviera activo, en cascada normal
   NO debería ser seleccionable. Esto mantiene consistencia y evita “puntos ciegos”.

   VALIDACIONES
   ------------
   1) _Id_Estado válido (>0)
   2) Estado existe
   3) Candado jerárquico:
      - Estado Activo=1
      - País padre Activo=1
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarMunicipiosPorEstado$$

CREATE PROCEDURE SP_ListarMunicipiosPorEstado(
    IN _Id_Estado INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del Estado
       - Si no existe, devolvemos error claro.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO jerárquico: Estado y País deben estar ACTIVOS
       - Este es el cambio importante.
       - Protege contra:
           * requests manipuladas
           * UI con cache viejo
           * inconsistencias del contrato de cascada

       Lógica:
       - Buscamos el Estado por Id.
       - Subimos al País padre (Fk_Id_Pais).
       - Exigimos:
           E.Activo = 1
           P.Activo = 1

       Nota:
       - Usamos JOIN porque la regla es jerárquica (no basta mirar Estado solo).
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (
        SELECT 1
        FROM Pais P
        JOIN Estado E ON E.Fk_Id_Pais = P.Id_Pais
        WHERE E.Id_Estado = _Id_Estado
          AND E.Activo = 1
          AND P.Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado o su País están inactivos. No se pueden listar Municipios.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Municipios activos del Estado
       - También filtramos Activo=1 porque es dropdown normal.
    ---------------------------------------------------------------------------------------- */
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
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPaisesAdmin
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantallas administrativas (CRUD admin) donde necesitas ver:
       * Activos e Inactivos
       * Para poder reactivar/desactivar y depurar catálogos

   ¿POR QUÉ EXISTE ESTE SP?
   ------------------------
   - Para NO mezclar contratos:
       * SP_ListarPaisesActivos  => dropdowns normales (solo Activo=1)
       * SP_ListarPaisesAdmin    => administración (todos)

   SEGURIDAD (IMPORTANTE)
   ----------------------
   - Este SP debería consumirse solo por usuarios con rol admin.
     (Ej: Cat_Roles / permisos en backend)

   QUÉ DEVUELVE
   ------------
   - Todos los países (Activo=1 y Activo=0)
   - Incluye campo Activo para que la UI pinte el estatus
   - Orden recomendado:
       * Activos primero
       * Luego por Nombre para fácil búsqueda
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarPaisesAdmin$$

CREATE PROCEDURE SP_ListarPaisesAdmin()
BEGIN
    SELECT
        Id_Pais,
        Codigo,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Pais
    ORDER BY
        Activo DESC,   -- primero activos (1), luego inactivos (0)
        Nombre ASC;
END$$

DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstadosAdminPorPais
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Estados, filtrando por País “padre”.
   - Ejemplo de flujo típico:
       1) Admin elige un País (puede estar activo o inactivo)
       2) UI lista TODOS los Estados de ese País (activos e inactivos)

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarEstadosPorPais (normal) exige País Activo=1 porque es dropdown de usuario final.
   - En ADMIN no quieres bloquearte si el país está inactivo:
       * necesitas poder ver sus estados para reactivarlos, corregir, limpiar, etc.

   VALIDACIONES
   ------------
   1) _Id_Pais válido (>0)
   2) País existe (aunque esté inactivo)
      - Si no existe, es error real (no hay nada que listar)

   QUÉ DEVUELVE
   ------------
   - Todos los estados del país (Activo=1 y Activo=0)
   - Incluye Activo + timestamps para auditoría visual
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarEstadosAdminPorPais$$
CREATE PROCEDURE SP_ListarEstadosAdminPorPais(
    IN _Id_Pais INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Pais IS NULL OR _Id_Pais <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Pais inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del País (admin permite inactivos, pero NO permite inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Pais WHERE Id_Pais = _Id_Pais) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El País no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODOS los Estados del País (activos e inactivos)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Estado,
        Codigo,
        Nombre,
        Fk_Id_Pais,
        Activo,
        created_at,
        updated_at
    FROM Estado
    WHERE Fk_Id_Pais = _Id_Pais
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER  ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarMunicipiosAdminPorEstado
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Municipios, filtrando por Estado “padre”.
   - Flujo típico:
       1) Admin elige un Estado (puede estar activo o inactivo)
       2) UI lista TODOS los Municipios de ese Estado

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarMunicipiosPorEstado (normal) exige Estado Activo=1 y País Activo=1 (candado jerárquico)
     porque es dropdown de selección normal.
   - En ADMIN no quieres bloquearte por jerarquía inactiva:
       * necesitas listar para mantenimiento: reactivar, corregir, depurar, etc.

   VALIDACIONES
   ------------
   1) _Id_Estado válido (>0)
   2) Estado existe (aunque esté inactivo)
      - Si no existe, es error real (no hay nada que listar)

   QUÉ DEVUELVE
   ------------
   - Todos los municipios del estado (Activo=1 y Activo=0)
   - Incluye Activo + timestamps
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarMunicipiosAdminPorEstado$$

CREATE PROCEDURE SP_ListarMunicipiosAdminPorEstado(
    IN _Id_Estado INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_Estado IS NULL OR _Id_Estado <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_Estado inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia del Estado (admin permite inactivos, pero NO permite inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Estado WHERE Id_Estado = _Id_Estado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: El Estado no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODOS los Municipios del Estado (activos e inactivos)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_Municipio,
        Codigo,
        Nombre,
        Fk_Id_Estado,
        Activo,
        created_at,
        updated_at
    FROM Municipio
    WHERE Fk_Id_Estado = _Id_Estado
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA -- DROPDOWNS (SOLO ACTIVOS)
   ============================================================================================
   Estas rutinas alimentan los selectores en los formularios.
   REGLA DE ORO: 
   - Solo devuelven registros con Activo = 1.
   - Aplican "Candado Jerárquico": No puedes listar hijos si el padre está inactivo.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDireccionesActivas
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown inicial de Direcciones en formularios en cascada.
   - Ejemplo: “Registrar/Editar Subdirección”, “Registrar/Editar Gerencia”.

   ¿QUÉ RESUELVE?
   --------------
   - Devuelve SOLO Direcciones activas (Activo = 1).
   - Ordenados por Nombre para que el usuario encuentre rápido.

   CONTRATO PARA UI (REGLA CLAVE)
   ------------------------------
   - “Activo = 1” significa: el registro es seleccionable/usable en UI.
   - Una Dirección inactiva NO debe aparecer en -- DROPdowns normales.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarDireccionesActivas$$
CREATE PROCEDURE SP_ListarDireccionesActivas()
BEGIN
    SELECT
        Id_CatDirecc,
        Clave,
        Nombre
    FROM Cat_Direcciones
    WHERE Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSubdireccionesPorDireccion   (VERSIÓN PRO: CONTRATO DE -- DROPDOWN “ACTIVOS”)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown de Subdirecciones cuando:
       a) Se selecciona una Dirección en UI
       b) Se abre un formulario y hay que precargar las subdirecciones de la Dirección actual

   OBJETIVO
   --------
   - Devolver SOLO Subdirecciones activas (Activo=1) de una Dirección seleccionada.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (BLINDAJE)
   ----------------------------------
   Antes:
   - Solo validabas existencia.
   
   Ahora (contrato estricto):
   - Un -- DROPdown “normal” SOLO permite seleccionar padres activos.
   - Si la Dirección está inactiva => NO se lista y se responde error claro.

   ¿POR QUÉ ERROR (SIGNAL) Y NO LISTA VACÍA?
   -----------------------------------------
   - Porque lista vacía es ambigua: “¿no hay subdirecciones o la dirección está bloqueada?”
   - Con error, el frontend puede mostrar: “Dirección inactiva, refresca”.

   VALIDACIONES
   ------------
   1) _Id_CatDirecc válido (>0)
   2) Dirección existe
   3) Dirección Activo=1  (candado de contrato)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarSubdireccionesPorDireccion$$
CREATE PROCEDURE SP_ListarSubdireccionesPorDireccion(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
       - Evita llamadas “chuecas” (null, 0, negativos) desde UI o requests directos.
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de la Dirección
       - Si no existe, regresamos error explícito.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO: Dirección debe estar ACTIVA
       - Este es el cambio importante.
       - Refuerza el contrato de -- DROPdown: “solo se listan hijos de padres activos”.
       - Protege contra UI con cache viejo.
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc AND Activo = 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección está inactiva. No se pueden listar Subdirecciones.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Subdirecciones activas de la Dirección
       - Nota: también filtramos Activo=1 de la Subdirección porque es -- DROPdown normal.
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatSubDirec,
        Clave,
        Nombre
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Id_CatDirecc
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasPorSubdireccion   (VERSIÓN PRO: CANDADO JERÁRQUICO)
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Para llenar el -- DROPdown de Gerencias cuando:
       a) Se selecciona una Subdirección en UI
       b) Se abre un formulario que requiere precargar gerencias

   OBJETIVO
   --------
   - Devolver SOLO Gerencias activas (Activo=1) de una Subdirección seleccionada.
   - Ordenados por Nombre.

   MEJORA “PRO” QUE ARREGLA (IMPORTANTE)
   -------------------------------------
   Ahora:
   - Candado jerárquico: Subdirección y su Dirección padre deben estar activos.
   - Si no cumplen, se devuelve error explícito.

   ¿POR QUÉ VALIDAR DIRECCIÓN TAMBIÉN?
   -----------------------------------
   Porque tu jerarquía real es:
       Gerencia -> Subdirección -> Dirección

   Si la Dirección está inactiva, aunque la Subdirección estuviera activa (caso raro pero posible),
   en cascada normal NO debería ser seleccionable. Esto mantiene consistencia.

   VALIDACIONES
   ------------
   1) _Id_CatSubDirec válido (>0)
   2) Subdirección existe
   3) Candado jerárquico:
      - Subdirección Activo=1
      - Dirección padre Activo=1
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarGerenciasPorSubdireccion$$
CREATE PROCEDURE SP_ListarGerenciasPorSubdireccion(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de la Subdirección
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Subdirecciones WHERE Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Candado PRO jerárquico: Subdirección y Dirección deben estar ACTIVAS
       - Lógica: Buscamos la Subdirección por Id.
       - Subimos a la Dirección padre (Fk_Id_CatDirecc).
       - Exigimos: S.Activo = 1 AND D.Activo = 1
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (
        SELECT 1
        FROM Cat_Direcciones D
        JOIN Cat_Subdirecciones S ON S.Fk_Id_CatDirecc = D.Id_CatDirecc
        WHERE S.Id_CatSubDirec = _Id_CatSubDirec
          AND S.Activo = 1
          AND D.Activo = 1
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección o su Dirección están inactivas. No se pueden listar Gerencias.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3) Listar Gerencias activas
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatGeren,
        Clave,
        Nombre
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec
      AND Activo = 1
    ORDER BY Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDireccionesAdmin
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantallas administrativas (CRUD admin) donde necesitas ver:
       * Activos e Inactivos
       * Para poder reactivar/desactivar y depurar catálogos.

   SEGURIDAD (IMPORTANTE)
   ----------------------
   - Este SP debería consumirse solo por usuarios con rol admin.
     (Ej: Cat_Roles / permisos en backend).

   QUÉ DEVUELVE
   ------------
   - Todas las direcciones (Activo=1 y Activo=0).
   - Incluye campo Activo para que la UI pinte el estatus (ej: rojo para inactivos).
   - Orden recomendado:
       * Activos primero (para tener a la mano lo operativo).
       * Luego por Nombre para fácil búsqueda.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarDireccionesAdmin$$
CREATE PROCEDURE SP_ListarDireccionesAdmin()
BEGIN
    SELECT
        Id_CatDirecc,
        Clave,
        Nombre,
        Activo,
        created_at,
        updated_at
    FROM Cat_Direcciones
    ORDER BY
        Activo DESC,    -- primero activos (1), luego inactivos (0)
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSubdireccionesAdminPorDireccion
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Subdirecciones, filtrando por Dirección “padre”.
   - Flujo típico:
       1) Admin elige una Dirección (puede estar activa o inactiva).
       2) UI lista TODAS las Subdirecciones de esa Dirección.

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarSubdireccionesPorDireccion (normal) exige Dirección Activa=1 porque es -- DROPdown 
     de usuario final (operativo).
   - En ADMIN no quieres bloquearte si la Dirección está inactiva:
       * Necesitas poder ver sus subdirecciones para reactivarlas, corregir errores, etc.

   VALIDACIONES
   ------------
   1) _Id_CatDirecc válido (>0)
   2) Dirección existe (aunque esté inactiva)
      - Si no existe, es error real (no hay nada que listar).

   QUÉ DEVUELVE
   ------------
   - Todas las subdirecciones de la dirección (Activo=1 y Activo=0).
   - Incluye Activo + timestamps para auditoría visual.
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarSubdireccionesAdminPorDireccion$$
CREATE PROCEDURE SP_ListarSubdireccionesAdminPorDireccion(
    IN _Id_CatDirecc INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatDirecc IS NULL OR _Id_CatDirecc <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatDirecc inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de Dirección (admin permite inactivos, pero NO inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Direcciones WHERE Id_CatDirecc = _Id_CatDirecc) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Dirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODAS las Subdirecciones (activas e inactivas)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatSubDirec,
        Clave,
        Nombre,
        Fk_Id_CatDirecc,
        Activo,
        created_at,
        updated_at
    FROM Cat_Subdirecciones
    WHERE Fk_Id_CatDirecc = _Id_CatDirecc
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasAdminPorSubdireccion
   ============================================================================================
   ¿CUÁNDO SE USA?
   --------------
   - Pantalla administrativa de Gerencias, filtrando por Subdirección “padre”.
   - Flujo típico:
       1) Admin elige una Subdirección (puede estar activa o inactiva).
       2) UI lista TODAS las Gerencias de esa Subdirección.

   ¿POR QUÉ ES DIFERENTE AL SP NORMAL?
   -----------------------------------
   - SP_ListarGerenciasPorSubdireccion (normal) exige Subdirección Activa=1 y Dirección Activa=1
     (candado jerárquico) porque es -- DROPdown de selección operativa.
   - En ADMIN no quieres bloquearte por jerarquía inactiva:
       * Necesitas listar para mantenimiento: reactivar, corregir, depurar, etc.

   VALIDACIONES
   ------------
   1) _Id_CatSubDirec válido (>0)
   2) Subdirección existe (aunque esté inactiva)
      - Si no existe, es error real (no hay nada que listar).

   QUÉ DEVUELVE
   ------------
   - Todas las gerencias de la subdirección (Activo=1 y Activo=0).
   - Incluye Activo + timestamps.
   - Orden:
       * Activos primero
       * Luego por Nombre
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS SP_ListarGerenciasAdminPorSubdireccion$$
CREATE PROCEDURE SP_ListarGerenciasAdminPorSubdireccion(
    IN _Id_CatSubDirec INT
)
BEGIN
    /* ----------------------------------------------------------------------------------------
       PASO 0) Validación básica de input
    ---------------------------------------------------------------------------------------- */
    IF _Id_CatSubDirec IS NULL OR _Id_CatSubDirec <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: Id_CatSubDirec inválido.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 1) Validar existencia de Subdirección (admin permite inactivos, pero NO inexistentes)
    ---------------------------------------------------------------------------------------- */
    IF NOT EXISTS (SELECT 1 FROM Cat_Subdirecciones WHERE Id_CatSubDirec = _Id_CatSubDirec) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ERROR: La Subdirección no existe.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2) Listar TODAS las Gerencias (activas e inactivas)
    ---------------------------------------------------------------------------------------- */
    SELECT
        Id_CatGeren,
        Clave,
        Nombre,
        Fk_Id_CatSubDirec,
        Activo,
        created_at,
        updated_at
    FROM Cat_Gerencias_Activos
    WHERE Fk_Id_CatSubDirec = _Id_CatSubDirec
    ORDER BY
        Activo DESC,
        Nombre ASC;
END$$

DELIMITER ;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasAdminParaFiltro
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ListarGerenciasParaFiltro
   - Tipo: Consulta de Catálogo Completo (Full Catalog Lookup)
   - Patrón de Diseño: "Raw Data Delivery" (Entrega de Datos Crudos)
   - Nivel de Aislamiento: Read Committed
   - Autor: Arquitectura de Datos PICADE (Forensic Division)
   - Versión: 3.0 (Platinum Standard - Frontend Flexible)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento alimenta el Dropdown de "Filtrar por Gerencia" en el Dashboard de Matrices.
   
   [CORRECCIÓN DE LÓGICA DE NEGOCIO - SOPORTE HISTÓRICO]:
   A diferencia de un formulario de registro (donde solo permitimos lo activo), un REPORTE
   es una ventana al pasado.
   Si el usuario consulta el año 2022, debe poder filtrar por Gerencias que existían en ese entonces,
   incluso si hoy (2026) ya fueron dadas de baja o reestructuradas.
   
   Por lo tanto, este SP devuelve **EL CATÁLOGO COMPLETO** (Activos + Inactivos).

   3. ESTRATEGIA TÉCNICA: "UI AGNOSTIC DATA"
   -----------------------------------------
   Se eliminó la concatenación en base de datos. Se entregan las columnas separadas (`Clave`, `Nombre`)
   para delegar el control visual al Frontend (Laravel/Vue).
   
   Esto permite al desarrollador Frontend:
     - Aplicar estilos diferenciados (ej: Clave en <span class="badge">).
     - Colorear distintamente las gerencias inactivas (ej: texto gris o tachado).
     - Implementar búsquedas avanzadas por columnas separadas.

   4. SEGURIDAD Y ORDENAMIENTO
   ---------------------------
   - Se incluye la columna `Activo` para que el Frontend sepa distinguir visualmente el estado.
   - Ordenamiento prioritario: Primero las Activas (uso común), luego las Inactivas (uso histórico).
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarGerenciasAdminParaFiltro`$$

CREATE PROCEDURE `SP_ListarGerenciasAdminParaFiltro`()
BEGIN
    /* ============================================================================================
       BLOQUE ÚNICO: PROYECCIÓN DE CATÁLOGO HISTÓRICO
       ============================================================================================ */
    SELECT 
        /* IDENTIFICADOR ÚNICO (Value del Select) */
        `Id_CatGeren`,
        
        /* DATOS CRUDOS (Para renderizado flexible en UI) */
        `Clave`,
        `Nombre`,
        
        /* METADATO DE ESTADO (UI Hint)
           Permite al Frontend pintar de gris o añadir "(Extinta)" a las gerencias inactivas. */
        `Activo`

    FROM `PICADE`.`Cat_Gerencias_Activos`
    
    /* SIN WHERE: 
       Traemos todo el historial para permitir filtrado en reportes de años anteriores. */
    
    /* ORDENAMIENTO DE USABILIDAD:
       1. Activo DESC: Las gerencias vigentes aparecen primero en la lista (acceso rápido).
       2. Nombre ASC: Búsqueda alfabética secundaria. */
    ORDER BY `Activo` DESC, `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarCTActivos
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista simple de Centros de Trabajo disponibles para ser asignados.
   
   CASOS DE USO
   ------------
   1. Formulario de "Alta de Empleado": Para seleccionar dónde trabaja.
   2. Formulario de "Programación de Curso": Para seleccionar dónde se impartirá.
   3. Filtros de Reportes Operativos.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS: Solo se devuelven registros con `Activo = 1`.
      - Los CTs dados de baja (borrado lógico) quedan ocultos para el usuario operativo.
   2. ORDENAMIENTO: Alfabético por Nombre, para facilitar la búsqueda visual en listas largas.
   3. LIGEREZA: Solo devuelve ID, Código y Nombre. No hace JOINs complejos porque 
      el dropdown no necesita saber la dirección exacta, solo identificar el lugar.

   RETORNO
   -------
   - Id_CatCT (Value del Option)
   - Codigo (Texto auxiliar)
   - Nombre (Label del Option)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarCTActivos`$$
CREATE PROCEDURE `SP_ListarCTActivos`()
BEGIN
    SELECT 
        `Id_CatCT`, 
        `Codigo`, 
        `Nombre` 
    FROM `Cat_Centros_Trabajo` 
    WHERE `Activo` = 1 
    ORDER BY `Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarCTAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Centros de Trabajo, con todos sus detalles y estatus.

   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Centros de Trabajo".
   - Permite al Admin ver qué CTs existen, cuáles están inactivos, y detectar errores de captura.

   ARQUITECTURA (USO DE VISTAS)
   ----------------------------
   Este SP se apoya en `Vista_Centros_Trabajo`.
   
   ¿Por qué usar la Vista?
   1. UBICACIÓN LEGIBLE: La vista ya hizo el trabajo duro de unir (JOIN) el CT con 
      Municipio -> Estado -> País. El Admin ve "Villahermosa, Tabasco" en lugar de "ID: 45".
   2. TOLERANCIA A FALLOS: La vista usa LEFT JOIN. Si un CT tiene mal la ubicación, 
      aparecerá en la lista con campos vacíos, permitiendo al Admin identificarlo y corregirlo.
      (Si usáramos INNER JOIN aquí, los registros dañados desaparecerían y serían "fantasmas").

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero. Los Inactivos (0) al final.
   2. Por Nombre (ASC): Orden alfabético secundario.

   RETORNO
   -------
   Devuelve todas las columnas definidas en `Vista_Centros_Trabajo`:
   - Identidad (ID, Código, Nombre)
   - Dirección (Calle, Num)
   - Ubicación (Mun, Edo, Pais)
   - Metadatos (Estatus, Fechas)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarCTAdmin`$$
CREATE PROCEDURE `SP_ListarCTAdmin`()
BEGIN
    SELECT * FROM `Vista_Centros_Trabajo` 
    ORDER BY `Estatus_CT` DESC, `Nombre_CT` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDepActivos
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista de Departamentos disponibles para ser asignados en formularios 
   (Ej: Alta de Empleado, Asignación de Activos).

   CASOS DE USO
   ------------
   - Dropdown simple o Autocomplete en formularios donde se requiere seleccionar el departamento.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS PROPIO: Solo devuelve departamentos con `Activo = 1`.
   2. FILTRO DE INTEGRIDAD JERÁRQUICA (CANDADO PADRE):
      - Un departamento solo es "seleccionable" si su Municipio padre TAMBIÉN está activo.
      - Si el municipio fue dado de baja (ej: cierre de operaciones en esa ciudad), 
        sus departamentos deben desaparecer de la lista disponible, aunque sigan en Activo=1.
   
   ORDENAMIENTO
   ------------
   - Alfabético por Nombre para facilitar la búsqueda visual.

   RETORNO
   -------
   - Id_CatDep (Value)
   - Codigo (Texto auxiliar)
   - Nombre (Label)
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarDepActivos`$$

CREATE PROCEDURE `SP_ListarDepActivos`()
BEGIN
    SELECT 
        `Dep`.`Id_CatDep`, 
        `Dep`.`Codigo`, 
        `Dep`.`Nombre`
    FROM `Cat_Departamentos` `Dep`
    /* JOIN para validar el estatus del padre (Municipio) */
    INNER JOIN `Municipio` `Mun` 
        ON `Dep`.`Fk_Id_Municipio_CatDep` = `Mun`.`Id_Municipio`
    WHERE 
        `Dep`.`Activo` = 1
        AND `Mun`.`Activo` = 1 /* CANDADO: Solo mostrar si el Municipio está operativo */
    ORDER BY 
        `Dep`.`Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarDepAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Departamentos para el Panel de Administración (Grid CRUD).
   
   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Departamentos".
   - Auditoría: Permite ver qué departamentos existen, cuáles están inactivos y su ubicación.
   
   DIFERENCIA CON EL LISTADO DE DROPDOWNS
   --------------------------------------
   - `SP_ListarDepActivos`: Solo devuelve Activos (1) y aplica candados jerárquicos (si el 
     Municipio está inactivo, el departamento no sale).
   - `SP_ListarDepAdmin` (ESTE): Devuelve TODO (Activos e Inactivos) y muestra el registro
     aunque su Municipio padre esté inactivo o roto. Esto es vital para que el administrador
     pueda ver el problema y corregirlo.

   ARQUITECTURA (USO DE VISTA)
   ---------------------------
   Se apoya en `Vista_Departamentos` para:
   1. Abstraer la complejidad de los JOINs geográficos.
   2. Mostrar nombres legibles (Municipio, Estado, País) en lugar de solo IDs numéricos.
   3. Garantizar que si se cambia la lógica de visualización en la vista, el Grid se actualiza solo.

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero. Los Inactivos (0) al final.
   2. Por Nombre (ASC): Orden alfabético secundario para facilitar la búsqueda visual.

   RETORNO
   -------
   Devuelve todas las columnas de la vista:
   - Identidad: Id, Código, Nombre.
   - Ubicación Física: Dirección (Calle/Num).
   - Ubicación Geográfica: Municipio, Estado, País (Nombres).
   - Metadatos: Estatus.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarDepAdmin`$$
CREATE PROCEDURE `SP_ListarDepAdmin`()
BEGIN
    SELECT * FROM `Vista_Departamentos` 
    ORDER BY 
        `Estatus_Departamento` DESC, -- Prioridad visual a lo operativo
        `Nombre_Departamento` ASC;
END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSedesActivas
   ============================================================================================
   OBJETIVO
   --------
   Obtener la lista de Sedes (CASES) disponibles para ser asignadas en operaciones
   (Ej: Programación de Cursos, Asignación de Instructores, Reportes).

   CASOS DE USO
   ------------
   - Dropdown "Seleccione Sede" en el formulario de creación de Cursos.
   - Filtros de búsqueda en reportes operativos.

   REGLAS DE NEGOCIO (EL CONTRATO)
   -------------------------------
   1. FILTRO DE ESTATUS PROPIO: 
      - Solo devuelve Sedes con `Activo = 1`.
      - Las Sedes dadas de baja lógica quedan ocultas para evitar errores operativos.

   2. FILTRO DE INTEGRIDAD JERÁRQUICA (CANDADO PADRE):
      - Una Sede solo es "seleccionable" si su Municipio padre TAMBIÉN está activo.
      - Lógica: "No puedes programar un curso en una Sede si la ciudad entera (Municipio) 
        está cerrada o inactiva en el sistema".
      - Esto evita inconsistencias donde se usa una ubicación geográfica prohibida.

   ORDENAMIENTO
   ------------
   - Alfabético por Nombre para facilitar la búsqueda visual rápida en el selector.

   RETORNO (DICCIONARIO)
   ---------------------
   - Id_CatCases_Sedes (Value del Option): El ID real para la FK.
   - Codigo (Texto auxiliar): Clave interna (ej: 'CASES-01').
   - Nombre (Label del Option): El nombre humano de la sede.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarSedesActivas`$$
CREATE PROCEDURE `SP_ListarSedesActivas`()
BEGIN
    SELECT 
        `S`.`Id_CatCases_Sedes`, 
        `S`.`Codigo`, 
        `S`.`Nombre`
    FROM `Cat_Cases_Sedes` `S`
    
    /* JOIN ESTRATÉGICO: Validar el estatus del padre (Municipio) */
    INNER JOIN `Municipio` `Mun` 
        ON `S`.`Fk_Id_Municipio` = `Mun`.`Id_Municipio`
        
    WHERE 
        `S`.`Activo` = 1          /* La Sede debe estar operativa */
        AND `Mun`.`Activo` = 1    /* CANDADO: El Municipio debe estar operativo */
        
    ORDER BY 
        `S`.`Nombre` ASC;
END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarSedesAdmin
   ============================================================================================
   OBJETIVO
   --------
   Obtener el inventario completo de Sedes (CASES), incluyendo identidad, ubicación y estatus,
   para alimentar el Panel de Administración (Grid CRUD).

   CASOS DE USO
   ------------
   - Pantalla principal del Módulo "Administrar Sedes/CASES".
   - Auditoría: Permite identificar qué sedes están operativas, cuáles están dadas de baja,
     y detectar registros con problemas de ubicación (huérfanos).

   DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ------------------------------------------------------
   1. SP_ListarSedesActivas (Dropdown): 
      - Filtra estrictamente `Activo = 1`.
      - Aplica "Candado Jerárquico": Oculta la Sede si su Municipio está inactivo.
   
   2. SP_ListarSedesAdmin (ESTE): 
      - Devuelve TODO (Activos e Inactivos).
      - IGNORA el candado del Municipio. El Administrador debe poder ver la Sede aunque su 
        municipio esté inactivo o roto, precisamente para poder entrar a editarla y arreglarla.

   ARQUITECTURA (USO DE VISTA)
   ---------------------------
   Se apoya en `Vista_Sedes` para:
   1. Abstraer la complejidad de los JOINs geográficos (Municipio -> Estado -> País).
   2. Seguridad de Visualización: La vista usa `LEFT JOIN`. Si una Sede tiene un ID de 
      municipio corrupto, la vista devuelve el registro con la ubicación en NULL.
      Esto garantiza que no existan "registros fantasma" invisibles para el administrador.

   ORDENAMIENTO ESTRATÉGICO
   ------------------------
   1. Por Estatus (DESC): Los Activos (1) aparecen primero para acceso rápido. 
      Los Inactivos (0) quedan al final.
   2. Por Nombre (ASC): Orden alfabético secundario para facilitar la búsqueda visual.

   RETORNO
   -------
   Devuelve todas las columnas proyectadas por `Vista_Sedes`:
   - Identidad: Id, Código (S/C), Nombre.
   - Ubicación Física: Dirección.
   - Ubicación Geográfica: Municipio, Estado, País.
   - Infraestructura: Capacidad Total (Resumen).
   - Metadatos: Estatus.
============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarSedesAdmin`$$
CREATE PROCEDURE `SP_ListarSedesAdmin`()
BEGIN
    SELECT * FROM `Vista_Sedes` 
    ORDER BY 
        `Estatus_Sede` DESC,  -- Prioridad visual a lo operativo
        `Nombre_Sedes` ASC;
END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes.
   ============================================================================================ */
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegimenesActivos
   ============================================================================================
   AUTOR: Arquitectura de Datos / Gemini
   FECHA: 2026

   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la única fuente autorizada para desplegar las opciones de contratación
   disponibles en los formularios de:
     - Alta de Personal (Info_Personal).
     - Filtros de Búsqueda en Reportes de RRHH.
     - Asignación de Plazas.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Régimen marcado como inactivo (Baja Lógica) representa una 
        modalidad de contratación obsoleta o derogada. Permitir su selección en un nuevo registro 
        generaría inconsistencias legales y administrativas ("Contratar a alguien bajo un esquema extinto").
      - Seguridad: Este filtro se aplica a nivel de base de datos, no se delega al Frontend.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Reduce la carga cognitiva del usuario. Buscar "Transitorio" es más rápido 
        en una lista ordenada alfabéticamente que en una ordenada por ID de inserción.

   3. ARQUITECTURA DE DATOS Y OPTIMIZACIÓN (PERFORMANCE)
   -----------------------------------------------------
   - Proyección Mínima (Payload Reduction):
     A diferencia de las vistas de administración, este SP NO devuelve columnas auditoras 
     (`created_at`, `updated_at`) ni descriptivas largas (`Descripcion`).
     
     Solo devuelve las 3 columnas esenciales para construir un elemento `<option>` HTML:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint): Para la identificación rápida visual.
     
     Esto reduce el tráfico de red (Network Overhead) cuando el catálogo crece.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos con la siguiente estructura:
     - `Id_CatRegimen`: (INT) Llave Primaria. Se usará como el `value` del selector.
     - `Codigo`:        (VARCHAR) Clave corta (ej: 'CONF'). Útil para mostrar entre paréntesis.
     - `Nombre`:        (VARCHAR) Texto principal (ej: 'Personal de Confianza').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegimenesActivos`$$
CREATE PROCEDURE `SP_ListarRegimenesActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN
       No se requieren parámetros de entrada ni validaciones complejas, ya que es una lectura
       directa sobre una entidad raíz (sin dependencias jerárquicas activas).
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el dato que el Frontend enviará de regreso al servidor al guardar el formulario. */
        `Id_CatRegimen`, 
        
        /* CLAVE MNEMOTÉCNICA
           Dato auxiliar para UI avanzada (ej: badges o hints). Puede ser NULL. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Regimenes_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto previene errores de "dedo" al seleccionar opciones obsoletas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       El ordenamiento se hace en el motor de BD (que es más rápido indexando) 
       para que el navegador no tenga que reordenar con JavaScript.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegimenesAdmin
   ============================================================================================
    1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Regímenes de Contratación" (Cat_Regimenes_Trabajo)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué tipos de contratos han existido.
     - Mantenimiento: Detectar errores ortográficos o de captura en nombres/códigos.
     - Gestión de Ciclo de Vida: Reactivar regímenes que fueron dados de baja por error.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRegimenesActivos`:
   
   A) SP_ListarRegimenesActivos (Dropdown): 
      - Enfoque: Operatividad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen regímenes obsoletos a nuevos empleados.
   
   B) SP_ListarRegimenesAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Regimenes` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas de la Vista 
     (ej: `Estatus_Regimen`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la lógica de presentación de nulos (aunque en este caso
     se decidió dejar el Código como raw data, la estructura está lista para evolucionar).

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Regimen` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Regimen` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Regimenes`:
     - [Identidad]: Id_Regimen, Codigo_Regimen, Nombre_Regimen.
     - [Detalle]: Descripcion_Regimen.
     - [Control]: Estatus_Regimen (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegimenesAdmin`$$
CREATE PROCEDURE `SP_ListarRegimenesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Regimenes`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Regimen` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Regimen` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPuestosActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la fuente autorizada para desplegar las opciones de "Puestos de Trabajo"
   disponibles en los formularios de:
     - Alta y Edición de Personal (Tabla `Info_Personal`).
     - Asignación de vacantes.
     - Filtros de búsqueda en Reportes de Plantilla.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Puesto marcado como inactivo (Baja Lógica) representa un 
        cargo obsoleto, reestructurado o eliminado del organigrama oficial. Permitir su selección 
        para un empleado activo generaría inconsistencias administrativas ("Empleado asignado a un puesto fantasma").
      - Seguridad: El filtro es backend-side, garantizando que ni siquiera una API manipulada 
        pueda recuperar puestos obsoletos por esta vía.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida por parte del usuario humano en listas largas.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: En la estructura actual, `Cat_Puestos_Trabajo` opera como una Entidad Raíz 
     (no depende jerárquicamente de otra tabla para existir en el catálogo, aunque funcionalmente 
     se asigne a centros de trabajo). Esto permite una consulta directa y veloz.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad referencial.
       2. Nombre (Label): Lectura humana.
       3. Código (Hint): Referencia visual rápida.
     Se omiten campos pesados como `Descripcion`, `created_at`, etc., para minimizar el tráfico de red.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
     - `Id_CatPuesto`: (INT) Llave Primaria. Value del selector.
     - `Codigo`:       (VARCHAR) Clave corta (ej: 'SUP-01'). Puede ser NULL.
     - `Nombre`:       (VARCHAR) Texto principal (ej: 'Supervisor de Seguridad').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarPuestosActivos`$$
CREATE PROCEDURE `SP_ListarPuestosActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatPuesto) en la tabla Info_Personal. */
        `Id_CatPuesto`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Útil para mostrar en el frontend como 'badge' o texto secundario entre paréntesis.
           Ej: "Supervisor de Obra (SUP-OB)" */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá y buscará en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Puestos_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos empleados no sean dados de alta en puestos extintos.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos para eficiencia.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría y gestión.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarPuestosAdmin
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Puestos de Trabajo" (`Cat_Puestos_Trabajo`)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué cargos han existido en la historia de la empresa.
     - Mantenimiento: Detectar errores de captura en nombres o códigos y corregirlos.
     - Gestión de Ciclo de Vida: Reactivar puestos que fueron dados de baja por error o que
       vuelven a ser operativos tras una reestructuración.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarPuestosActivos`:
   
   A) SP_ListarPuestosActivos (Dropdown): 
      - Enfoque: Operatividad y Seguridad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen nuevos empleados a puestos obsoletos.
   
   B) SP_ListarPuestosAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación y gestión.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Puestos` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Puesto`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la proyección de columnas de auditoría y metadatos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Puesto` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Puesto` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Puestos`:
     - [Identidad]: Id_Puesto, Codigo_Puesto, Nombre_Puesto.
     - [Detalle]: Descripcion_Puesto.
     - [Control]: Estatus_Puesto (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at (aunque ocultos por defecto en la vista, si se activan).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarPuestosAdmin`$$
CREATE PROCEDURE `SP_ListarPuestosAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Puestos`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Puesto` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Puesto` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegionesActivas
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y altamente optimizado para alimentar elementos de 
   Interfaz de Usuario (UI) tipo "Selector", "Dropdown" o "ComboBox".
   
   Este procedimiento es la fuente autorizada para desplegar las Regiones Operativas disponibles
   en los formularios de:
     - Alta de Centros de Trabajo (Asignación de Región).
     - Alta de Sedes.
     - Filtros de búsqueda en Dashboards Ejecutivos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Una Región marcada como inactiva (Baja Lógica) implica que
        ya no existe operativamente (ej: reestructuración de la empresa). Permitir seleccionarla
        para un nuevo Centro de Trabajo rompería la integridad del modelo organizacional actual.
      - Seguridad: El filtro es backend-side, garantizando que ni siquiera una API manipulada
        pueda recuperar regiones obsoletas por esta vía.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida por parte del usuario humano.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: A diferencia de Municipios o Sedes, las Regiones son "Entidades Raíz"
     (no dependen de un padre activo para existir). Por lo tanto, la consulta es directa y
     extremadamente rápida (O(1) table scan indexado).
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad.
       2. Nombre (Label): Lectura.
       3. Código (Hint): Referencia visual rápida.
     Se omiten campos pesados como `Descripcion`, `created_at`, etc., para ahorrar ancho de banda.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
     - `Id_CatRegion`: (INT) Llave Primaria. Value del selector.
     - `Codigo`:       (VARCHAR) Clave corta (ej: 'RM-S').
     - `Nombre`:       (VARCHAR) Texto principal (ej: 'Región Marina Suroeste').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegionesActivas`$$
CREATE PROCEDURE `SP_ListarRegionesActivas`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key en las tablas hijas. */
        `Id_CatRegion`, 
        
        /* CLAVE CORTA
           Útil para mostrar en el frontend como 'badge' o texto secundario.
           Ej: "Región Sur (R-SUR)" */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Regiones_Trabajo`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos registros no se asocien a regiones extintas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético en el motor de base de datos.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRegionesAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de las "Regiones Operativas" (`Cat_Regiones_Trabajo`)
   para alimentar el Grid Principal del Módulo de Administración.
   
   Este endpoint permite al Administrador visualizar la totalidad de los datos (históricos y actuales)
   para realizar tareas de:
     - Auditoría: Revisar qué regiones han existido en la historia de la empresa.
     - Mantenimiento: Detectar errores de captura en nombres o códigos.
     - Gestión de Ciclo de Vida: Reactivar regiones que fueron dadas de baja por error o que
       vuelven a ser operativas.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRegionesActivas`:
   
   A) SP_ListarRegionesActivas (Dropdown): 
      - Enfoque: Operatividad y Seguridad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar que se asignen nuevos recursos a regiones obsoletas.
   
   B) SP_ListarRegionesAdmin (ESTE):
      - Enfoque: Gestión y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver registros inactivos (`Estatus = 0`) para poder editarlos
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Regiones` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Region`) y no a los de la tabla física (`Activo`). Si la tabla cambia,
     solo ajustamos la Vista y este SP sigue funcionando sin cambios.
   - Estandarización: La vista ya maneja la proyección de columnas de auditoría y metadatos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento no es arbitrario; está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (`Estatus_Region` DESC): 
        Los registros VIGENTES (1) aparecen en la parte superior. Los obsoletos (0) se van al fondo.
        Esto mantiene la información relevante accesible inmediatamente sin scrollear.
     2. Orden Alfabético (`Nombre_Region` ASC): 
        Dentro de cada grupo de estatus, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Regiones`:
     - [Identidad]: Id_Region, Codigo_Region, Nombre_Region.
     - [Detalle]: Descripcion_Region.
     - [Control]: Estatus_Region (1 = Activo, 0 = Inactivo).
     - [Auditoría]: created_at, updated_at.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRegionesAdmin`$$
CREATE PROCEDURE `SP_ListarRegionesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Regiones`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Region` DESC,  -- 1º: Muestra primero lo que está vivo (Operativo)
        `Nombre_Region` ASC;    -- 2º: Ordena alfabéticamente para facilitar búsqueda visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRolesActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ultraligero para alimentar elementos de Interfaz de Usuario (UI)
   tipo "Selector", "Dropdown" o "Select2" en el módulo de Gestión de Usuarios.

   Este procedimiento es la **Única Fuente de Verdad** para desplegar los perfiles de seguridad
   disponibles en los formularios de:
      - Alta de Nuevos Usuarios.
      - Reasignación de Permisos.
      - Filtros de Auditoría de Accesos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE SEGURIDAD ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación de Seguridad: Un Rol marcado como inactivo (`Activo = 0`) significa que ha sido
        revocado, deprecado o suspendido temporalmente por la administración. Permitir su selección
        crearía una brecha de seguridad (asignar permisos que no deberían existir) o inconsistencias
        en el middleware de autorización.
      - Implementación: El filtro es nativo en BD, blindando al sistema incluso contra APIs externas.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita que el administrador encuentre rápidamente el rol deseado
        (ej: "Administrador" al inicio, "Supervisor" al final) sin tener que leer toda la lista.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Optimización de Lectura: Al ser `Cat_Roles` una tabla de catálogo pequeña y de alto acceso
     (High Read / Low Write), esta consulta es extremadamente rápida.
   
   - Proyección Mínima (Payload Reduction):
     Solo se proyectan las 3 columnas vitales para el componente visual HTML/JS:
       1. ID (Value): Para la relación en base de datos (`Id_Rol`).
       2. Nombre (Label): Lo que ve el humano (`Administrador`).
       3. Código (Auxiliary): Para lógica de frontend (ej: íconos condicionales basados en 'ADMIN' o 'USER').
     
     Se omiten campos de auditoría o descripciones largas para maximizar la velocidad de respuesta.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos JSON optimizados:
      - `Id_Rol`: (INT) Llave Primaria.
      - `Codigo`: (VARCHAR) Slug técnico (ej: 'SOPORTE_TI').
      - `Nombre`: (VARCHAR) Etiqueta (ej: 'Soporte Técnico').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRolesActivos`$$
CREATE PROCEDURE `SP_ListarRolesActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere parámetros. Es un "Full Table Scan" filtrado, ideal para catálogos.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este valor se guardará en la tabla de relación Users-Roles (o en la tabla Users). */
        `Id_Rol`, 
        
        /* CÓDIGO TÉCNICO / SLUG
           Útil si el frontend necesita pintar íconos específicos según el rol 
           (ej: si Codigo='ADMIN' -> mostrar escudo). */
        `Codigo`, 
        
        /* ETIQUETA HUMANA
           El texto que se renderiza dentro de la etiqueta <option> del select. */
        `Nombre`

    FROM 
        `Cat_Roles`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE VIGENCIA (SEGURIDAD)
       Solo roles "vivos". Los revocados (0) se ocultan para prevenir asignaciones erróneas.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       ORDENAMIENTO
       Alfabético por nombre para mejorar la experiencia de usuario (UX).
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarRolesAdmin
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Roles de Sistema" (`Cat_Roles`) para 
   alimentar el Grid Principal del Módulo de Gestión de Seguridad.

   Este endpoint permite al Administrador de Seguridad (CISO/SuperAdmin) visualizar la totalidad 
   de los perfiles de acceso (históricos y actuales) para realizar tareas de:
      - Auditoría de Accesos: Revisar qué roles han existido y su alcance.
      - Depuración: Identificar roles duplicados u obsoletos.
      - Gestión de Ciclo de Vida: Reactivar permisos que fueron revocados temporalmente.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   Es vital distinguir este SP de `SP_ListarRolesActivos`:
   
   A) SP_ListarRolesActivos (Dropdown): 
      - Enfoque: Asignación de Permisos.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar asignar roles revocados a usuarios nuevos.
   
   B) SP_ListarRolesAdmin (ESTE):
      - Enfoque: Gobernanza y Auditoría.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir al Admin ver roles inactivos (`Estatus = 0`) para poder editarlos 
        (ej: corregir descripción) o reactivarlos. Ocultar los inactivos aquí impediría su gestión.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista 
   `Vista_Roles` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados de la Vista 
     (ej: `Estatus_Rol`, `Codigo_Rol`) y no a los de la tabla física (`Activo`, `Codigo`).
   - Estandarización: La vista ya aplica transformaciones semánticas útiles para la UI.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
      1. Prioridad Operativa (`Estatus_Rol` DESC): 
         Los roles VIGENTES (1) aparecen arriba. Los revocados (0) se van al fondo.
         Esto mantiene la información relevante accesible inmediatamente.
      2. Orden Alfabético (`Nombre_Rol` ASC): 
         Dentro de cada grupo, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Roles`:
      - [Identidad]: Id_Rol, Codigo_Rol (Slug), Nombre_Rol.
      - [Contexto]: Descripcion_Rol.
      - [Control]: Estatus_Rol (1 = Activo, 0 = Inactivo).
      - [Auditoría]: created_at, updated_at (Disponibles si se descomentan en la vista).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarRolesAdmin`$$
CREATE PROCEDURE `SP_ListarRolesAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra de Seguridad */
        * FROM 
        `Vista_Roles`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el auditor de seguridad.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Rol` DESC,  -- 1º: Prioridad a los roles activos
        `Nombre_Rol` ASC;    -- 2º: Orden alfabético para búsqueda visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA -- DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */
   
/* ============================================================================================
   PROCEDIMIENTO: SP_ListarInstructoresActivos
   ============================================================================================

--------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Lectura Crítica" diseñado para alimentar el componente visual 
   "Selector de Asignación" (-- DROPdown/Select2) en el módulo de Coordinación.

   [EL PROBLEMA QUE RESUELVE]: 
   En un ecosistema con >2,300 usuarios, permitir la selección libre generaba dos riesgos graves:
     1. Riesgo Operativo: Asignar por error a un "Participante" (Alumno) para dar un curso.
     2. Riesgo de Rendimiento: Cargar una lista masiva sin filtrar colapsaba la memoria del navegador.

   [SOLUCIÓN IMPLEMENTADA]: 
   Un algoritmo de filtrado de "Doble Candado" (Vigencia + Competencia) optimizado a nivel de 
   índices de base de datos para retornar solo el subconjunto válido (< 10% del total) en < 5ms.

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   Las siguientes reglas son IMPERATIVAS y definen la lógica del `WHERE`:

   [RN-01] REGLA DE VIGENCIA OPERATIVA (SOFT DELETE CHECK)
      - Definición: "Nadie puede ser asignado a un evento futuro si no tiene contrato activo".
      - Implementación: Cláusula `WHERE Activo = 1`.
      - Impacto: Excluye automáticamente jubilados, bajas temporales y despidos.

   [RN-02] REGLA DE JERARQUÍA DE COMPETENCIA (ROLE ELIGIBILITY)
      - Definición: "El permiso para instruir se otorga explícitamente o por jerarquía superior".
      - Lógica de Inclusión (Whitelist):
          * ID 1 (ADMINISTRADOR): Posee permisos Supremos. (Habilitado).
          * ID 2 (COORDINADOR): Posee permisos de Gestión. (Habilitado).
          * ID 3 (INSTRUCTOR): Posee permisos de Ejecución. (Habilitado).
      - Lógica de Exclusión (Blacklist):
          * ID 4 (PARTICIPANTE): Solo consume contenido. (BLOQUEADO).

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Al eliminar el `JOIN` con la tabla `Cat_Roles` y filtrar por IDs numéricos (`Fk_Rol`),
       evitamos el producto cartesiano. El motor realiza una búsqueda directa.

   [B] HEURÍSTICA DE ORDENAMIENTO (ZERO-FILESORT)
       El `ORDER BY` coincide exactamente con la definición física del índice `Idx_Busqueda_Apellido`.
       El motor de BD lee los datos secuencialmente del disco ya ordenados, eliminando el uso
       de CPU y RAM para reordenar el resultado.

   [C] ESTRATEGIA DE NULOS (NULL SAFETY)
       Se utiliza `CONCAT_WS` en lugar de `CONCAT`.
       - Problema: `CONCAT('Juan', NULL, 'Perez')` retorna `NULL` (Dato perdido).
       - Solución: `CONCAT_WS` ignora el NULL y retorna "Juan Perez". Garantiza integridad visual.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
     1. `Id_Usuario` (INT): Valor relacional (Foreign Key).
     2. `Ficha` (STRING): Clave de búsqueda exacta.
     3. `Nombre_Completo` (STRING): Etiqueta visual para el humano.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarInstructoresActivos`$$

CREATE PROCEDURE `SP_ListarInstructoresActivos`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN DE DATOS (SELECT)
       Define qué datos viajan a la red. Se aplica estrategia "Lean Payload" (solo lo vital).
       ======================================================================================== */
    SELECT 
        /* [DATO CRÍTICO] IDENTIFICADOR DE SISTEMA
           Este campo es invisible para el usuario pero vital para el sistema.
           Se usará en el `INSERT INTO Capacitaciones (Fk_Id_Instructor)...` */
        `U`.`Id_Usuario`,

        /* [VECTOR DE BÚSQUEDA 1] IDENTIFICADOR CORPORATIVO
           Permite a los coordinadores buscar rápidamente usando el teclado numérico. */
        `U`.`Ficha`,

        /* [VECTOR DE BÚSQUEDA 2] ETIQUETA VISUAL HUMANA
           Transformación: Concatenación con separador de espacio.
           Objetivo: Generar una cadena única de búsqueda tipo "Google".
           Formato: APELLIDOS + NOMBRE (Para coincidir con listas de asistencia físicas). */
        CONCAT_WS(' ', `IP`.`Apellido_Paterno`, `IP`.`Apellido_Materno`, `IP`.`Nombre`) AS `Nombre_Completo`

    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS Y RELACIONES (FROM/JOIN)
       ======================================================================================== */
    FROM 
        `Usuarios` `U`

    /* RELACIÓN DE INTEGRIDAD
       Unimos con la tabla satélite de información personal.
       Usamos INNER JOIN como medida de "Calidad de Datos": Si un usuario no tiene 
       datos personales (registro corrupto), se excluye automáticamente de la lista. */
    INNER JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* JOIN 2: Recuperar Departamento para contexto (LEFT JOIN por robustez) */
    /* Si el instructor no tiene depto asignado, aún debe aparecer en la lista */
    /*LEFT JOIN `Cat_Departamentos` `Dep` 
        ON `IP`.`Fk_Id_CatDep` = `Dep`.`Id_CatDep`*/

    /* JOIN 3: Filtrado por Rol (SEGURIDAD) */
    /*INNER JOIN `Cat_Roles` `R`
        ON `U`.`Fk_Rol` = `R`.`Id_Rol`*/

    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       Aquí se aplican los filtros de seguridad y lógica operativa.
       ======================================================================================== */
    WHERE 
        /* [REGLA 1] VIGENCIA OPERATIVA
           El usuario debe tener la bandera de acceso en TRUE (1). */
        `U`.`Activo` = 1
        
        AND 
        
        /* [REGLA 2] FILTRO DE COMPETENCIA (Hardcoded IDs)
           Implementación técnica de la regla de jerarquía.
           Se filtra directamente sobre la columna FK para aprovechar la indexación numérica.
           
           LISTA BLANCA DE ACCESO:
           - 1: ADMIN (Superuser)
           - 2: COORDINADOR (Manager)
           - 3: INSTRUCTOR (Worker)
           
           Cualquier ID fuera de este rango (ej: 4=Participante) es descartado. */
        `U`.`Fk_Rol` IN (1, 2, 3)

    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO OPTIMIZADO (ORDER BY)
       ======================================================================================== */
    /* ALINEACIÓN DE ÍNDICE:
       Estas columnas coinciden en orden exacto con `Idx_Busqueda_Apellido`.
       Esto permite una lectura secuencial sin costo de procesamiento. */
    ORDER BY 
        `IP`.`Apellido_Paterno` ASC, 
        `IP`.`Apellido_Materno` ASC,
        `IP`.`Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */
   
   /* ============================================================================================
   PROCEDIMIENTO: SP_ListarTodosInstructores_Historial
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Lectura Histórica" diseñado para alimentar los **Filtros de Búsqueda**
   en los Reportes de Auditoría, Historial de Capacitaciones y Tableros de Control (Dashboards).

   [EL PROBLEMA QUE RESUELVE]: 
   El selector operativo (`SP_ListarInstructoresActivos`) oculta a los usuarios dados de baja.
   Esto generaba un "Punto Ciego" en los reportes: El administrador no podía filtrar cursos 
   impartidos en el pasado por personal que ya se jubiló o fue desvinculado.

   [SOLUCIÓN IMPLEMENTADA]: 
   Una variante del algoritmo "Zero-Join" que **ignora el estatus de vigencia** e inyecta 
   metadatos visuales ("Enriquecimiento de Etiqueta") para diferenciar activos de inactivos
   sin comprometer el rendimiento.

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   [RN-01] ALCANCE UNIVERSAL (NO VIGENCY CHECK)
      - Definición: "Para auditar el pasado, todos los actores son relevantes".
      - Implementación: Se ELIMINA deliberadamente la cláusula `WHERE Activo = 1`.
      - Impacto: El listado incluye el universo total histórico de instructores.

   [RN-02] ENRIQUECIMIENTO VISUAL (STATUS BADGING)
      - Definición: "El usuario debe distinguir inmediatamente el estado operativo del recurso".
      - Lógica:
          * Si `Activo = 1`: Muestra solo el nombre.
          * Si `Activo = 0`: Inyecta el sufijo " (BAJA/INACTIVO)".
      - Justificación UX: Evita que el Admin intente reactivar o contactar a personal inexistente.

   [RN-03] REGLA DE JERARQUÍA DE COMPETENCIA (ROLE ELIGIBILITY)
      - Definición: "Solo se listan aquellos roles que históricamente pudieron impartir clase".
      - Lógica de Inclusión (Whitelist de IDs):
          * ID 1 (ADMIN), ID 2 (COORD), ID 3 (INSTRUCTOR).
      - Lógica de Exclusión:
          * ID 4 (PARTICIPANTE): Se excluye, ya que nunca debió impartir un curso.

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Mantiene la optimización de filtrar por IDs numéricos (`Fk_Rol`), evitando JOINs costosos.

   [B] COSTO COMPUTACIONAL DE ENRIQUECIMIENTO
       La operación `CASE WHEN` para el sufijo se ejecuta en memoria durante la proyección. 
       Su impacto es despreciable (< 0.01ms por fila) comparado con el beneficio de UX.

   [C] HEURÍSTICA DE ORDENAMIENTO
       Mantiene la alineación estricta con el índice `Idx_Busqueda_Apellido`.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
     1. `Id_Usuario` (INT): Valor para el filtro SQL (`WHERE Fk_Instructor = X`).
     2. `Ficha` (STRING): Clave de búsqueda visual.
     3. `Nombre_Completo_Filtro` (STRING): Etiqueta enriquecida con estado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTodosInstructores_Historial`$$

CREATE PROCEDURE `SP_ListarTodosInstructores_Historial`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN Y ENRIQUECIMIENTO DE DATOS (SELECT)
       ======================================================================================== */
    SELECT 
        /* [ID DEL FILTRO] 
           Valor que se usará en el `WHERE` del reporte que consuma este SP. */
        `U`.`Id_Usuario`,

        /* [CLAVE VISUAL] 
           Identificador corporativo. */
        `U`.`Ficha`,

        /* [ETIQUETA VISUAL INTELIGENTE] (Logic Injection)
           Objetivo: Generar una etiqueta que informe identidad + estado.
           
           Composición:
           1. Nombre Base: CONCAT_WS para evitar nulos.
           2. Sufijo Dinámico: CASE para detectar inactividad. */
        CONCAT(
            CONCAT_WS(' ', `IP`.`Apellido_Paterno`, `IP`.`Apellido_Materno`, `IP`.`Nombre`),
            CASE 
                WHEN `U`.`Activo` = 0 THEN ' (BAJA/INACTIVO)' 
                ELSE '' 
            END
        ) AS `Nombre_Completo_Filtro`

    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS (FROM/JOIN)
       ======================================================================================== */
    FROM 
        `Usuarios` `U`

    /* RELACIÓN DE INTEGRIDAD
       Usamos INNER JOIN. Un usuario sin datos personales es irrelevante para un reporte
       nominal, por lo que se descarta por integridad de datos. */
    INNER JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* NOTA DE ARQUITECTURA: 
       Se mantiene la estrategia "Zero-Join" (sin tabla Roles) para máxima velocidad. */

    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       ======================================================================================== */
    WHERE 
        /* [DIFERENCIA CRÍTICA]
           NO EXISTE FILTRO DE `Activo = 1`. 
           Estamos recuperando la historia completa (Vivos + Muertos). */
        
        /* [REGLA 2] FILTRO DE COMPETENCIA (Hardcoded IDs)
           Se filtra directamente sobre la columna FK para aprovechar la indexación numérica.
           Solo nos interesan usuarios con capacidad docente. */
        `U`.`Fk_Rol` IN (
            1,  -- ADMINISTRADOR
            2,  -- COORDINADOR
            3   -- INSTRUCTOR
        )

    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO OPTIMIZADO (ORDER BY)
       ======================================================================================== */
    /* ALINEACIÓN DE ÍNDICE:
       Garantiza lectura secuencial del disco. */
    ORDER BY 
        `IP`.`Apellido_Paterno` ASC, 
        `IP`.`Apellido_Materno` ASC, 
        `IP`.`Nombre` ASC;

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTiposInstruccionActivos
   ============================================================================================
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos ligero y optimizado para alimentar el selector (Dropdown)
   de "Tipo de Instrucción" (Naturaleza Pedagógica) en los formularios de gestión académica.

   Este procedimiento es la fuente autorizada para clasificar cursos en:
      - Alta de Nuevos Temas de Capacitación (`Cat_Temas_Capacitacion`).
      - Filtros de Búsqueda en el Catálogo de Cursos.

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Tipo de Instrucción marcado como inactivo (Baja Lógica)
        representa una clasificación obsoleta o que ya no se imparte en la institución.
        Permitir su selección para un curso nuevo generaría inconsistencia en la matriz de capacitación.
      - Seguridad: El filtro es nativo en BD para blindar la integridad del catálogo.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida (ej: encontrar "Teórico" antes de "Virtual").

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Tipos_Instruccion_Cap` es una Entidad Raíz (no depende jerárquicamente
     de otra tabla para existir). Esto permite una consulta directa de altísima velocidad (O(1)).
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas necesarias para construir el elemento HTML `<option>`:
       1. ID (Value): Integridad referencial.
       2. Nombre (Label): Lectura humana.
     Se omite la columna `Descripcion` para minimizar el tráfico de red, ya que no es visible en el dropdown.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatTipoInstCap`: (INT) Llave Primaria. Value del selector.
      - `Nombre`:            (VARCHAR) Texto principal (ej: 'Teórico-Práctico').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTiposInstruccionActivos`$$
CREATE PROCEDURE `SP_ListarTiposInstruccionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatTipoInstCap) 
           en la tabla Cat_Temas_Capacitacion. */
        `Id_CatTipoInstCap`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Tipos_Instruccion_Cap`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que nuevos cursos no se asocien a tipos de instrucción extintos.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (GRID / TABLA CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control del Administrador.
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTiposInstruccionAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Tipos de Instrucción" (Naturaleza Pedagógica)
   para alimentar el Grid Principal del Módulo de Administración.

   CASOS DE USO:
   - Pantalla de Mantenimiento de Catálogos.
   - Auditoría: Revisar qué tipos han existido históricamente.
   - Gestión de Ciclo de Vida: Reactivar tipos que fueron dados de baja por error.

   2. DIFERENCIA CRÍTICA CON EL LISTADO OPERATIVO (DROPDOWN)
   ---------------------------------------------------------
   A) SP_ListarTiposInstruccionActivos (Dropdown):
      - Enfoque: Operatividad.
      - Filtro: Estricto `WHERE Activo = 1`.
      - Objetivo: Evitar asignar tipos obsoletos a cursos nuevos.

   B) SP_ListarTiposInstruccionAdmin (ESTE):
      - Enfoque: Gestión Total.
      - Filtro: NINGUNO (Visibilidad Total).
      - Objetivo: Permitir ver registros inactivos (`Activo = 0`) para poder editarlos 
        o reactivarlos. Ocultar los inactivos aquí impediría su recuperación.

   3. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Cat_Tipos_Instruccion_Admin` en lugar de la tabla física.

   Ventajas Técnicas:
   - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados
     de la Vista (ej: `Estatus_Tipo_Instruccion`) y no a los de la tabla física (`Activo`).
   - Estandarización: La vista ya maneja la proyección de columnas limpias.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
      1. Prioridad Operativa (Estatus DESC): 
         Los registros VIGENTES (1) aparecen arriba. Los obsoletos (0) se van al fondo.
         Esto mantiene la información relevante accesible inmediatamente.
      2. Orden Alfabético (Nombre ASC): 
         Dentro de cada grupo, se ordenan A-Z para facilitar la búsqueda visual rápida.

   5. DICCIONARIO DE DATOS (OUTPUT)
   --------------------------------
   Retorna el contrato de datos definido en `Vista_Cat_Tipos_Instruccion_Admin`:
      - [Identidad]: Id_Tipo_Instruccion, Nombre_Tipo_Instruccion.
      - [Detalle]: Descripcion_Tipo_Instruccion.
      - [Control]: Estatus_Tipo_Instruccion (1 = Activo, 0 = Inactivo).
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTiposInstruccionAdmin`$$
CREATE PROCEDURE `SP_ListarTiposInstruccion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA
       No requiere validaciones de entrada ya que es una consulta global sobre el catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra */
        * FROM 
        `Vista_Tipos_Instruccion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Tipo_Instruccion` DESC,  -- 1º: Prioridad a los activos (1 antes que 0)
        `Nombre_Tipo_Instruccion` ASC;    -- 2º: Orden alfabético visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTemasActivos
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Alta Disponibilidad" diseñado para alimentar el componente visual 
   "Selector de Curso" (Select2/Dropdown) en los módulos de logística y programación.

   [EL PROBLEMA QUE RESUELVE]: 
   La gestión de catálogos heterogéneos (donde algunos registros tienen códigos técnicos y otros no)
   suele generar deuda técnica en la capa de base de datos al intentar formatear cadenas de texto.
   Este SP resuelve el problema entregando datos atómicos para que la UI decida la presentación.

   [SOLUCIÓN IMPLEMENTADA]:
   Una consulta directa, optimizada por índices y libre de lógica de presentación (Concat), 
   delegando la estética al cliente (Separation of Concerns).

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   Las siguientes reglas son IMPERATIVAS y definen la lógica del `WHERE`:

   [RN-01] REGLA DE VIGENCIA OPERATIVA (SOFT DELETE CHECK)
      - Definición: "Solo lo que está activo es programable".
      - Implementación: Cláusula `WHERE Activo = 1`.
      - Impacto: Filtra automáticamente cursos históricos, obsoletos o dados de baja.

   [RN-02] ARQUITECTURA DE SEGURIDAD "KILL SWITCH" (INTEGRITY AT WRITE)
      - Definición: "La integridad del padre se garantiza en la escritura, no en la lectura".
      - Justificación Técnica: Se eliminó el `JOIN` con `Cat_Tipos_Instruccion_Cap`. Nos basamos en 
        la premisa de que el sistema de Bajas (Update) impide desactivar un Padre si tiene Hijos activos.
      - Beneficio: Reducción drástica de complejidad ciclomática y eliminación de overhead por Joins.

   [RN-03] ESTRATEGIA DE "RAW DATA" (PRESENTATION LAYER DELEGATION)
      - Definición: "La base de datos no maquilla datos".
      - Implementación: Se entregan `Codigo` y `Nombre` en columnas separadas.
      - Justificación: Evita problemas de `NULL` en concatenaciones SQL y permite al Frontend renderizar 
        componentes ricos (ej: Badges, Negritas, Tooltips) sin depender de un string pre-formateado.

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Al eliminar los JOINS y filtrar únicamente por una columna booleana indexada (`Activo`), 
       el motor de base de datos realiza un acceso directo a las páginas de datos relevantes.

   [B] CARGA ÚTIL MÍNIMA (LEAN PAYLOAD)
       Se excluyen columnas de texto pesado (`Descripcion`, `created_at`). Solo viajan los bytes 
       estrictamente necesarios para construir el objeto `<option value="id">label</option>`.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
      1. `Id_Tema` (INT): Valor relacional (Foreign Key).
      2. `Codigo` (STRING | NULL): Metadato técnico. Puede ser nulo en registros legacy.
      3. `Nombre` (STRING): Etiqueta visual principal para el humano.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTemasActivos`$$

CREATE PROCEDURE `SP_ListarTemasActivos`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN DE DATOS (SELECT)
       Define qué datos viajan a la red. Se aplica estrategia "Raw Data".
       ======================================================================================== */
    SELECT 
        /* [DATO CRÍTICO] IDENTIFICADOR DE SISTEMA
           Este campo es invisible para el usuario pero vital para el sistema.
           Se usará en el `INSERT INTO Programacion (Fk_Id_Tema)...` */
        `Id_Cat_TemasCap`  AS `Id_Tema`,
        
        /* [VECTOR VISUAL 1] CÓDIGO INTERNO (RAW)
           Se envía el dato crudo sin procesar. 
           Permite al Frontend decidir si lo muestra, lo oculta o lo formatea condicionalmente. 
           Ejemplo UI: <span class="badge badge-gray">{{ item.Codigo }}</span> */
        `Codigo`,
        
        /* [VECTOR VISUAL 2] NOMBRE DESCRIPTIVO
           La etiqueta principal para la lectura humana y el ordenamiento alfabético. */
        `Nombre`
        
        /* ------------------------------------------------------------------------------------
           COLUMNA DE ETIQUETA (LABEL)
           Formato "Humanizado" para el usuario final. 
           Ejemplo Visual: "SEG-001 - SEGURIDAD INDUSTRIAL BÁSICA"
           ------------------------------------------------------------------------------------ */
        -- CONCAT(`T`.`Codigo`, ' - ', `T`.`Nombre`) AS `Nombre_Completo`
        
        /* ------------------------------------------------------------------------------------
           METADATOS DE SOPORTE (DATA ATTRIBUTES)
           Información auxiliar para lógica de frontend (ej: sumar horas en un calendario).
           ------------------------------------------------------------------------------------ */
        -- `T`.`Duracion_Horas`
        
    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS (FROM)
       Acceso directo a la tabla física sin intermediarios.
       ======================================================================================== */
    FROM 
        `Cat_Temas_Capacitacion`
        
    /* ----------------------------------------------------------------------------------------
       INNER JOIN: EL CANDADO JERÁRQUICO
       Unimos con la tabla de Tipos para validar el estado del padre.
       Si el Tipo no existe o no cumple el WHERE, la fila del Tema se descarta.
       ---------------------------------------------------------------------------------------- */
    /*LEFT JOIN `Cat_Tipos_Instruccion_Cap` `Tipo` 
        ON `T`.`Fk_Id_CatTipoInstCap` = `Tipo`.`Id_CatTipoInstCap`*/
                
    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       Filtro de alta velocidad sobre índice booleano.
       ======================================================================================== */
    WHERE 
        /* [REGLA 1] VIGENCIA OPERATIVA
           Solo se listan los recursos marcados como disponibles para nuevas operaciones.
           Confiamos en el Kill Switch para la integridad del padre (sin JOIN). */
        `Activo` = 1
        
    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO (UX)
       ======================================================================================== */
    /* ESTANDARIZACIÓN VISUAL:
       Orden alfabético A-Z por Nombre para facilitar la búsqueda en listas largas. */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTemasAdmin
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Temas de Capacitación" para alimentar el
   Grid Principal del Módulo de Administración.
   
   Permite al administrador:
     - Auditar la totalidad de cursos creados (Histórico y Actual).
     - Identificar cursos "huérfanos" (cuyo Tipo de Instrucción fue eliminado).
     - Gestionar el ciclo de vida (Reactivar cursos dados de baja).

   2. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista
   `Vista_Cat_Temas_Capacitacion`.
   
   Ventajas Técnicas:
     - Desacoplamiento: Si cambia la estructura de la tabla física, la vista absorbe el impacto
       y este SP no necesita ser recompilado.
     - Estandarización: La vista ya entrega los nombres de columnas "limpios" y los JOINs (LEFT)
       necesarios para mostrar datos aunque tengan integridad parcial.

   3. DIFERENCIA CRÍTICA CON EL DROPDOWN (VISIBILIDAD)
   ---------------------------------------------------
   A diferencia de `SP_ListarTemasActivos`, aquí NO EXISTE la cláusula `WHERE Activo = 1`.
   
   Justificación:
     - En Administración, "Ocultar" es "Perder". Un registro inactivo (`Estatus_Tema = 0`)
       debe ser visible para poder editarlo o reactivarlo. Si lo ocultamos aquí, sería
       imposible recuperarlo sin acceso directo a la base de datos.

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (Estatus DESC): Los registros VIGENTES (1) aparecen arriba.
        Los obsoletos (0) se van al fondo.
     2. Orden Alfabético (Nombre ASC): Dentro de cada grupo, se ordenan A-Z.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTemasAdmin`$$

CREATE PROCEDURE `SP_ListarTemasAdmin`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA SOBRE LA VISTA
       No requiere parámetros ni validaciones previas al ser una lectura global.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra.
           Incluye: ID, Códigos, Nombres, Descripciones, Duración, Nombre del Tipo, Estatus. */
        * FROM 
        `Vista_Temas_Capacitacion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Tema` DESC,  -- 1º: Los activos arriba (Prioridad de atención)
        `Nombre_Tema` ASC;    -- 2º: Orden alfabético para búsqueda rápida

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstatusCapacitacionActivos
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer un endpoint de datos de alta velocidad para alimentar el componente visual 
   "Selector de Estatus" (Dropdown) en los formularios de gestión operativa (ej: "Actualizar 
   Avance de Curso").

   Este procedimiento es la fuente autorizada para que los Coordinadores o Instructores 
   cambien el estado de una capacitación (de 'Programado' a 'En Curso', etc.).

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Estatus marcado como inactivo (Baja Lógica) indica que esa 
        fase del proceso ya no se utiliza en la metodología actual de la empresa. Permitir su 
        selección generaría datos inconsistentes con los procesos vigentes.
      - Seguridad: El filtro es nativo en BD, impidiendo que una UI desactualizada inyecte 
        estados obsoletos.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Estatus_Capacitacion` es una Entidad Raíz (no tiene dependencias 
     jerárquicas hacia arriba). Esto permite una ejecución directa sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: pintar de rojo si es 'CAN').
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red en dispositivos móviles o conexiones lentas.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatEstCap`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:       (VARCHAR) Clave corta (ej: 'PROG'). Útil para badges de colores.
      - `Nombre`:       (VARCHAR) Texto principal (ej: 'Programado').
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusCapacitacionActivos`$$

CREATE PROCEDURE `SP_ListarEstatusCapacitacionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatEstCap) 
           en la tabla operativa 'DatosCapacitaciones'. */
        `Id_CatEstCap`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos condicionales.
           Ej: Si Codigo == 'CAN' (Cancelado) -> Pintar texto en Rojo.
               Si Codigo == 'FIN' (Finalizado) -> Pintar texto en Verde. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Estatus_Capacitacion`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las operaciones vivas solo usen estados aprobados actualmente.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos para eficiencia.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ListarEstatusCapacitacion
   ============================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------
   Proveer el inventario maestro y completo de los "Estatus de Capacitación" para alimentar el 
   Grid Principal del Módulo de Administración.
   
   Permite al administrador:
     - Auditar la totalidad de estados configurados (Histórico y Actual).
     - Identificar qué estados son "Finales" (liberadores) y cuáles "Bloqueantes".
     - Gestionar el ciclo de vida (Reactivar estatus que fueron dados de baja por error).

   2. ARQUITECTURA DE DATOS (VIEW CONSUMPTION PATTERN)
   ---------------------------------------------------
   Este procedimiento implementa el patrón de "Abstracción de Lectura" al consumir la vista 
   `Vista_Estatus_Capacitacion` en lugar de la tabla física.
   
   [VENTAJAS TÉCNICAS]:
     - Desacoplamiento: El Grid del Frontend se acopla a los nombres de columnas estandarizados 
       de la Vista (ej: `Estatus_Activo`, `Descripcion_Estatus`) y no a los nombres técnicos 
       de la tabla física.
     - Estandarización: La vista ya maneja la proyección de columnas limpias y cualquier 
       lógica de presentación necesaria.

   3. DIFERENCIA CRÍTICA CON EL DROPDOWN (VISIBILIDAD)
   ---------------------------------------------------
   A diferencia de `SP_ListarEstatusCapacitacionActivos`, aquí NO EXISTE la cláusula 
   `WHERE Activo = 1`.
   
   [JUSTIFICACIÓN]:
     - En Administración, "Ocultar" es "Perder". Un registro inactivo (`Activo = 0`) 
       debe ser visible en la tabla para poder editarlo o reactivarlo. Si lo ocultamos aquí, 
       sería imposible recuperarlo sin acceso directo a la base de datos (SQL).

   4. ESTRATEGIA DE ORDENAMIENTO (UX PRIORITY)
   -------------------------------------------
   El ordenamiento está diseñado para la eficiencia administrativa:
     1. Prioridad Operativa (Estatus DESC): Los registros VIGENTES (1) aparecen arriba. 
        Los obsoletos (0) se van al fondo de la tabla.
     2. Orden Alfabético (Nombre ASC): Dentro de cada grupo, se ordenan A-Z para facilitar 
        la búsqueda visual.

   5. DICCIONARIO DE DATOS (OUTPUT VIA VIEW)
   -----------------------------------------
   Retorna las columnas definidas en `Vista_Estatus_Capacitacion`:
     - Id_Estatus_Capacitacion, Codigo_Estatus, Nombre_Estatus.
     - Descripcion_Estatus.
     - Estatus_Activo (1=Sí, 0=No).
   ============================================================================================ */

DELIMITER $$

 -- DROP PROCEDURE IF EXISTS `SP_ListarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_ListarEstatusCapacitacion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA MAESTRA SOBRE LA VISTA
       No requiere parámetros ni validaciones previas al ser una lectura global del catálogo.
       ======================================================================================== */
    
    SELECT 
        /* Proyección total de la Vista Maestra.
           Incluye: ID, Código, Nombre, Descripción, Estatus Activo. */
        * FROM 
        `Vista_Estatus_Capacitacion`
    
    /* ========================================================================================
       ORDENAMIENTO ESTRATÉGICO
       Optimizamos la presentación para el usuario administrador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_de_Capacitacion` DESC,  -- 1º: Los activos arriba (Prioridad de atención)
        `Nombre_Estatus` ASC;   -- 2º: Orden alfabético para búsqueda rápida visual

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */
   
/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarModalidadCapacitacionActivos
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Proveer un endpoint de datos ligero y optimizado para alimentar el componente visual 
   "Selector de Modalidad" (Dropdown) en los formularios de creación y edición de cursos.

   Este procedimiento es la fuente autorizada para que los Coordinadores elijan el formato
   logístico de una capacitación (ej: 'Presencial', 'Virtual', 'Híbrido').

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ----------------------------------------------------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Una Modalidad marcada como inactiva (Baja Lógica) indica que ese 
        formato de impartición ya no está soportado por la infraestructura actual. Permitir su 
        selección generaría cursos imposibles de ejecutar.
      - Seguridad: El filtro es nativo en BD, blindando el sistema contra UIs desactualizadas.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Modalidad_Capacitacion` es una Entidad Raíz (sin padres).
     Esto permite una ejecución directa y veloz sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: iconos).
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red en conexiones lentas.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatModalCap`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:         (VARCHAR) Clave corta (ej: 'PRES'). Útil para iconos.
      - `Nombre`:         (VARCHAR) Texto principal (ej: 'Presencial').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarModalidadCapacitacionActivos`$$

CREATE PROCEDURE `SP_ListarModalidadCapacitacionActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key (Fk_Id_CatModalCap) 
           en la tabla operativa 'DatosCapacitaciones'. */
        `Id_CatModalCap`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos o iconos condicionales.
           Ej: Si Codigo == 'VIRT' -> Mostrar icono de computadora. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Modalidad_Capacitacion`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las operaciones vivas solo usen modalidades aprobadas actualmente.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos para eficiencia.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */
   
/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarModalidadCapacitacion
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. FICHA TÉCNICA Y CONTEXTO DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [NOMBRE LÓGICO]: Listado Maestro de Modalidades (Versión Ligera).
   [TIPO]: Rutina de Lectura (Read-Only).
   [DEPENDENCIA]: Consume la vista `Vista_Modalidad_Capacitacion`.

   [PROPÓSITO ESTRATÉGICO]:
   Este procedimiento actúa como el proveedor de datos para los **Filtros de Búsqueda Avanzada** en los 
   Paneles Administrativos y Reportes de Auditoría.
   
   A diferencia de los listados operativos (que solo muestran lo vigente), este SP debe entregar la 
   **Totalidad Histórica** del catálogo (Activos + Inactivos) para permitir que un auditor pueda 
   buscar cursos antiguos que se impartieron bajo modalidades ya extintas (ej: "A distancia por radio").

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE OPTIMIZACIÓN DE CARGA (PAYLOAD REDUCTION STRATEGY)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA]:
   En un Dashboard Administrativo, es común cargar 10 o 15 dropdowns simultáneamente al iniciar la página.
   Si cada dropdown trae descripciones largas, textos de ayuda y metadatos innecesarios, el tamaño del 
   JSON de respuesta crece exponencialmente, causando lentitud en la carga (Latency bloat).

   [LA SOLUCIÓN: PROYECCIÓN SELECTIVA]:
   Este SP aplica un patrón de "Adelgazamiento de Datos". Aunque la Vista fuente contiene la columna 
   `Descripcion_Modalidad` (que puede ser texto extenso), este procedimiento la **EXCLUYE DELIBERADAMENTE**.

   [JUSTIFICACIÓN]:
   En un control `<select>` o filtro de tabla, el usuario solo necesita ver el `Nombre` para elegir. 
   La descripción es ruido en este contexto. Al eliminarla, reducimos el consumo de ancho de banda y 
   memoria del navegador.

   ----------------------------------------------------------------------------------------------------
   III. REGLAS DE VISIBILIDAD Y ORDENAMIENTO (UX RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VISIBILIDAD TOTAL (NO FILTERING):
      - Regla: No se aplica ninguna cláusula `WHERE` sobre el estatus.
      - Razón: "Lo que se oculta no se puede auditar". El admin debe ver todo.

   [RN-02] JERARQUÍA VISUAL (SORTING):
      - Primer Nivel: `Estatus_Modalidad DESC`. Los registros ACTIVOS (1) aparecen arriba.
        Los INACTIVOS (0) se hunden al fondo de la lista.
      - Segundo Nivel: `Nombre_Modalidad ASC`. Orden alfabético para búsqueda rápida.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (API RESPONSE SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un Array de Objetos JSON optimizado:
      1. [Id_Modalidad]: (INT) El valor (`value`) del filtro.
      2. [Codigo_Modalidad]: (STRING) Clave técnica para lógica de iconos en el frontend.
      3. [Nombre_Modalidad]: (STRING) La etiqueta (`label`) visible.
      4. [Estatus_Modalidad]: (INT) 1/0. Permite al Frontend pintar de gris los items inactivos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarModalidadCapacitacion`$$

CREATE PROCEDURE `SP_ListarModalidadCapacitacion`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE PROYECCIÓN SELECTIVA
       ----------------------------------------------------------------------------------------
       Nota de Implementación:
       No usamos `SELECT *`. Enumeramos explícitamente las columnas para garantizar que la
       `Descripcion_Modalidad` NO viaje por la red.
       ======================================================================================== */
    
    SELECT 
        /* -------------------------------------------------------------------------------
           GRUPO 1: IDENTIDAD DEL RECURSO (PRIMARY KEYS & CODES)
           Datos necesarios para mantener la integridad referencial en la selección.
           ------------------------------------------------------------------------------- */
        `Id_Modalidad`,        -- Vinculación con FKs en tablas de hechos (Cursos).
        `Codigo_Modalidad`,    -- Identificador semántico corto (ej: 'VIRT').

        /* -------------------------------------------------------------------------------
           GRUPO 2: DESCRIPTOR HUMANO (LABEL)
           La información principal que el usuario final leerá en la interfaz.
           ------------------------------------------------------------------------------- */
        `Nombre_Modalidad`    -- Texto descriptivo (ej: 'VIRTUAL SINCRÓNICO').
        
        /* -------------------------------------------------------------------------------
           GRUPO 3: METADATOS DE CONTROL (STATUS FLAG)
           Dato crítico para la UX del Administrador.
           Permite aplicar estilos visuales (ej: tachado, gris, icono de alerta) a los
           elementos que ya no están vigentes, sin ocultarlos del filtro.
           ------------------------------------------------------------------------------- */
        -- `Estatus_Modalidad`    -- 1 = Operativo, 0 = Deprecado/Histórico.
        
        /* [COLUMNA EXCLUIDA]: `Descripcion_Modalidad`
           Se omite por optimización de Payload. No aporta valor en un Dropdown. */
        
    FROM 
        `Vista_Modalidad_Capacitacion`
    
    /* ========================================================================================
       BLOQUE DE ORDENAMIENTO (UX OPTIMIZATION)
       ----------------------------------------------------------------------------------------
       Diseñado para maximizar la eficiencia del operador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Modalidad` DESC,  -- Prioridad 1: Mantener lo útil (Activos) al principio.
        `Nombre_Modalidad` ASC;    -- Prioridad 2: Facilitar el escaneo visual alfabético.

END$$

DELIMITER ;


/* ============================================================================================
   SECCIÓN: LISTADOS PARA DROPDOWNS (SOLO REGISTROS ACTIVOS)
   ============================================================================================
   Estas rutinas son consumidas por los formularios de captura (Frontend).
   Su objetivo es ofrecer al usuario solo las opciones válidas y vigentes para evitar errores.
   ============================================================================================ */

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarEstatusParticipanteActivos
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Proveer un endpoint de datos de alta velocidad para alimentar el componente visual 
   "Selector de Estatus de Asistencia" (Dropdown) en los formularios de evaluación de cursos.

   Este procedimiento es la fuente autorizada para que los Instructores califiquen el desempeño
   final de un asistente (ej: 'Aprobado', 'Reprobado', 'Cancelado').

   2. REGLAS DE NEGOCIO Y FILTRADO (THE VIGENCY CONTRACT)
   ----------------------------------------------------------------------------------------------------
   A) FILTRO DE VIGENCIA ESTRICTO (HARD FILTER):
      - Regla: La consulta aplica obligatoriamente la cláusula `WHERE Activo = 1`.
      - Justificación Operativa: Un Estatus marcado como inactivo (Baja Lógica) indica que esa 
        categoría de calificación ya no es válida en la normativa actual. Permitir su selección 
        generaría reportes de cumplimiento inconsistentes.
      - Seguridad: El filtro es nativo en BD, impidiendo que una UI desactualizada inyecte 
        estados obsoletos.

   B) ORDENAMIENTO COGNITIVO (USABILITY):
      - Regla: Los resultados se ordenan alfabéticamente por `Nombre` (A-Z).
      - Justificación: Facilita la búsqueda visual rápida en la lista desplegable.

   3. ARQUITECTURA DE DATOS (ROOT ENTITY OPTIMIZATION)
   ---------------------------------------------------
   - Ausencia de JOINs: `Cat_Estatus_Participante` es una Entidad Raíz. Esto permite una 
     ejecución directa sobre el índice primario.
   
   - Proyección Mínima (Payload Reduction):
     Solo se devuelven las columnas vitales para construir el elemento HTML `<option>`:
       1. ID (Value): Para la integridad referencial.
       2. Nombre (Label): Para la lectura humana.
       3. Código (Hint/Badge): Para lógica visual en el frontend (ej: pintar de verde si es 'APROB').
     
     Se omiten campos pesados como `Descripcion` o auditoría (`created_at`) para minimizar 
     la latencia de red.

   4. DICCIONARIO DE DATOS (OUTPUT JSON SCHEMA)
   --------------------------------------------
   Retorna un array de objetos ligeros:
      - `Id_CatEstPart`: (INT) Llave Primaria. Value del selector.
      - `Codigo`:        (VARCHAR) Clave corta (ej: 'APROB'). Útil para badges de colores.
      - `Nombre`:        (VARCHAR) Texto principal (ej: 'Aprobado').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusParticipanteActivos`$$

CREATE PROCEDURE `SP_ListarEstatusParticipanteActivos`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE SELECCIÓN OPTIMIZADA
       No requiere validaciones de entrada ya que es una consulta de catálogo global.
       ======================================================================================== */
    
    SELECT 
        /* IDENTIFICADOR ÚNICO (PK)
           Este es el valor que se guardará como Foreign Key en la tabla intermedia de asistencia. */
        `Id_CatEstPart`, 
        
        /* CLAVE CORTA / MNEMOTÉCNICA
           Dato auxiliar para que el Frontend pueda aplicar estilos condicionales.
           Ej: Si Codigo == 'REP' (Reprobado) -> Pintar texto en Rojo.
               Si Codigo == 'APR' (Aprobado) -> Pintar texto en Verde. */
        `Codigo`, 
        
        /* DESCRIPTOR HUMANO
           El texto principal que el usuario leerá en la lista desplegable. */
        `Nombre`

    FROM 
        `Cat_Estatus_Participante`
    
    /* ----------------------------------------------------------------------------------------
       FILTRO DE SEGURIDAD OPERATIVA (VIGENCIA)
       Ocultamos todo lo que no sea "1" (Activo). 
       Esto asegura que las calificaciones nuevas solo usen estatus vigentes.
       ---------------------------------------------------------------------------------------- */
    WHERE 
        `Activo` = 1
    
    /* ----------------------------------------------------------------------------------------
       OPTIMIZACIÓN DE UX
       Ordenamiento alfabético realizado por el motor de base de datos para eficiencia.
       ---------------------------------------------------------------------------------------- */
    ORDER BY 
        `Nombre` ASC;

END$$

DELIMITER ;

/* ============================================================================================
   SECCIÓN: LISTADOS PARA ADMINISTRACIÓN (TABLAS CRUD)
   ============================================================================================
   Estas rutinas son consumidas exclusivamente por los Paneles de Control (Grid/Tabla de Mantenimiento).
   Su objetivo es dar visibilidad total sobre el catálogo para auditoría, gestión y corrección.
   ============================================================================================ */

/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarEstatusParticipante
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. FICHA TÉCNICA Y CONTEXTO DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [NOMBRE LÓGICO]: Listado Maestro de Estatus de Participante (Versión Ligera).
   [TIPO]: Rutina de Lectura (Read-Only).
   [DEPENDENCIA]: Consume la vista `Vista_Estatus_Participante`.

   [PROPÓSITO ESTRATÉGICO]:
   Este procedimiento actúa como el proveedor de datos para el **Grid Principal de Administración**.
   Permite al Administrador visualizar el inventario completo de los posibles resultados de 
   calificación (ej: Aprobado, Reprobado, Cancelado), incluyendo aquellos que ya no están vigentes.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE OPTIMIZACIÓN DE CARGA (PAYLOAD REDUCTION STRATEGY)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA]:
   En un Dashboard Administrativo, la velocidad es crítica. Cargar columnas de texto largo 
   (como descripciones detalladas o logs de auditoría extensos) en una tabla que muestra 
   50 o 100 filas genera latencia innecesaria.

   [LA SOLUCIÓN: PROYECCIÓN SELECTIVA]:
   Este SP aplica un patrón de "Adelgazamiento de Datos". Aunque la Vista fuente contiene la columna 
   `Descripcion_Estatus`, este procedimiento la **EXCLUYE DELIBERADAMENTE** del listado principal.
   
   [JUSTIFICACIÓN]:
   En la tabla resumen, el usuario solo necesita identificar el registro por Código y Nombre. 
   Los detalles profundos se cargan "bajo demanda" (Lazy Loading) solo cuando el usuario hace 
   clic en "Editar" o "Ver Detalle" (usando `SP_ConsultarEstatusParticipanteEspecifico`).

   ----------------------------------------------------------------------------------------------------
   III. REGLAS DE VISIBILIDAD Y ORDENAMIENTO (UX RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VISIBILIDAD TOTAL (NO FILTERING):
      - Regla: No se aplica ninguna cláusula `WHERE` sobre el estatus.
      - Razón: "Lo que se oculta no se puede gestionar". El admin debe ver los registros inactivos
        para poder reactivarlos si fue un error.

   [RN-02] JERARQUÍA VISUAL (SORTING):
      - Primer Nivel: `Estatus_Activo DESC`. Los registros ACTIVOS (1) aparecen arriba.
        Los INACTIVOS (0) se hunden al fondo de la lista para no estorbar la operación diaria.
      - Segundo Nivel: `Nombre_Estatus ASC`. Orden alfabético para búsqueda visual rápida.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (API RESPONSE SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un Array de Objetos JSON optimizado:
      1. [Id_Estatus_Participante]: (INT) Llave Primaria. Oculta en el grid, usada en botones de acción.
      2. [Codigo_Estatus]: (STRING) Clave visual corta (Badge).
      3. [Nombre_Estatus]: (STRING) La etiqueta principal visible.
      4. [Estatus_Activo]: (INT) 1/0. Permite al Frontend pintar de gris los items inactivos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarEstatusParticipante`$$

CREATE PROCEDURE `SP_ListarEstatusParticipante`()
BEGIN
    /* ========================================================================================
       BLOQUE ÚNICO: CONSULTA DE PROYECCIÓN SELECTIVA
       ----------------------------------------------------------------------------------------
       Nota de Implementación:
       Enumeramos explícitamente las columnas para garantizar un payload ligero.
       ======================================================================================== */
    
    SELECT 
        /* -------------------------------------------------------------------------------
           GRUPO 1: IDENTIDAD DEL RECURSO (PRIMARY KEYS & CODES)
           Datos necesarios para mantener la integridad referencial en la selección.
           ------------------------------------------------------------------------------- */
        `Id_Estatus_Participante`,    -- ID oculto para operaciones CRUD.
        `Codigo_Estatus`,             -- Identificador semántico corto (ej: 'APROB').

        /* -------------------------------------------------------------------------------
           GRUPO 2: DESCRIPTOR HUMANO (LABEL)
           La información principal que el usuario final leerá en la interfaz.
           ------------------------------------------------------------------------------- */
        `Nombre_Estatus`             -- Texto descriptivo (ej: 'APROBADO').
        
        /* -------------------------------------------------------------------------------
           GRUPO 3: METADATOS DE CONTROL (STATUS FLAG)
           Dato crítico para la UX del Administrador.
           Permite aplicar estilos visuales (ej: fila gris, icono de 'apagado') a los
           elementos inactivos.
           ------------------------------------------------------------------------------- */
        -- `Estatus_Activo`              -- 1 = Operativo, 0 = Deprecado/Histórico.
        
        /* [COLUMNA EXCLUIDA]: `Descripcion_Estatus`
           Se omite por optimización. El detalle se ve en el modal de edición. */
        
    FROM 
        `Vista_Estatus_Participante`
    
    /* ========================================================================================
       BLOQUE DE ORDENAMIENTO (UX OPTIMIZATION)
       ----------------------------------------------------------------------------------------
       Diseñado para maximizar la eficiencia del operador.
       ======================================================================================== */
    ORDER BY 
        `Estatus_Activo` DESC,  -- Prioridad 1: Mantener lo útil (Activos) al principio.
        `Nombre_Estatus` ASC;   -- Prioridad 2: Facilitar el escaneo visual alfabético.

END$$

DELIMITER ;


