
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

    FROM `Picade`.`Cat_Gerencias_Activos`
    
    /* SIN WHERE: 
       Traemos todo el historial para permitir filtrado en reportes de años anteriores. */
    
    /* ORDENAMIENTO DE USABILIDAD:
       1. Activo DESC: Las gerencias vigentes aparecen primero en la lista (acceso rápido).
       2. Nombre ASC: Búsqueda alfabética secundaria. */
    ORDER BY `Activo` DESC, `Nombre` ASC;

END$$

DELIMITER ;