/* ====================================================================================================
   PROCEDIMIENTO: SP_ListarGerenciasParaFiltro
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ListarGerenciasParaFiltro
   - Tipo: Consulta de Búsqueda Rápida (Lookup Query)
   - Patrón de Diseño: "Flat List Projection" (Proyección de Lista Plana)
   - Nivel de Aislamiento: Read Committed
   - Complejidad: Baja (O(N) sobre índice de nombres)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento resuelve un problema crítico de **Experiencia de Usuario (UX)** en el Dashboard.
   
   [PROBLEMA]:
   En los formularios de registro, usamos "Combos en Cascada" (Dirección -> Subdirección -> Gerencia)
   para mantener la integridad estructural. Sin embargo, en un **Reporte o Dashboard**, obligar al
   usuario a realizar 3 clics para filtrar una tabla es ineficiente y frustrante.
   
   [SOLUCIÓN]:
   Proveer una lista unificada y plana de todas las unidades operativas (Gerencias), permitiendo
   al Coordinador filtrar la Matriz de Información con **un solo clic**.

   3. ESTRATEGIA TÉCNICA: "PRE-FORMATTED SEARCH LABEL"
   ---------------------------------------------------
   En lugar de enviar datos crudos al Frontend y obligar a JavaScript a formatearlos, la base de datos
   entrega el campo `Texto_Mostrar` ya concatenado (`CLAVE | NOMBRE`).
   
   Esto tiene dos beneficios:
     1. Estandarización: La visualización es idéntica en Web, Móvil y Excel.
     2. Búsqueda: Facilita a los componentes de UI (como Select2 o Vue-Multiselect) buscar
        tanto por la Clave (ej: "MANT") como por el Nombre (ej: "Mantenimiento").

   4. SEGURIDAD DE DATOS
   ---------------------
   - Filtro Estricto (`Activo = 1`): Solo se muestran gerencias vivas. Esto evita que se filtren
     reportes sobre unidades organizacionales extintas, manteniendo el Dashboard limpio.
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ListarGerenciasParaFiltro`$$

CREATE PROCEDURE `SP_ListarGerenciasParaFiltro`()
BEGIN
    /* ============================================================================================
       BLOQUE ÚNICO: PROYECCIÓN DE CATALOGO PLANO
       No requiere parámetros de entrada.
       ============================================================================================ */
    SELECT 
        /* IDENTIFICADOR ÚNICO */
        `Id_CatGeren`,
        
        /* ETIQUETA VISUAL (UX LABEL)
           Concatenación estratégica para facilitar la búsqueda visual y por teclado.
           Formato: "CLAVE | NOMBRE DE GERENCIA" */
        CONCAT(`Clave`, ' | ', `Nombre`) AS `Texto_Mostrar`

    FROM `Picade`.`Cat_Gerencias_Activos`
    
    /* REGLA DE NEGOCIO:
       Solo mostrar unidades operativas vigentes. Las gerencias dadas de baja no deben
       aparecer en los filtros de nuevos reportes para evitar ruido cognitivo. */
    WHERE `Activo` = 1
    
    /* ORDENAMIENTO ALFABÉTICO (HUMAN FRIENDLY)
       Facilita el escaneo visual en listas largas. */
    ORDER BY `Nombre` ASC;

END$$

DELIMITER ;
