/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO CENTROS DE TRABAJO
   =================================================================================
   OBJETIVO:
   Verificar la integridad, concurrencia, validación geográfica atómica y
   ciclo de vida (CRUD) de los Centros de Trabajo.
   ================================================================================= */

USE Picade;

/* ---------------------------------------------------------------------------------
   PRE-REQUISITOS: GENERAR DATOS GEOGRÁFICOS DE PRUEBA
   Necesitamos dos rutas geográficas distintas para probar la "Mudanza Incoherente".
   Ruta A: PAIS A -> EDO A -> MUN A
   Ruta B: PAIS B -> EDO B -> MUN B
   --------------------------------------------------------------------------------- */
-- Crear Ruta A
CALL SP_RegistrarUbicaciones('M_QA_01', 'MUNICIPIO QA A', 'E_QA_01', 'ESTADO QA A', 'P_QA_01', 'PAIS QA A');
SET @IdPaisA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_01');
SET @IdEdoA  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_01');
SET @IdMunA  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_01');

-- Crear Ruta B
CALL SP_RegistrarUbicaciones('M_QA_02', 'MUNICIPIO QA B', 'E_QA_02', 'ESTADO QA B', 'P_QA_02', 'PAIS QA B');
SET @IdPaisB = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_02');
SET @IdEdoB  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_02');
SET @IdMunB  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_02');


/* =================================================================================
   FASE 1: CREACIÓN Y NORMALIZACIÓN
   Objetivo: Probar el registro, limpieza de espacios y reglas de duplicidad.
   ================================================================================= */

-- 1.1. Registro Exitoso (Happy Path)
-- [ESPERADO]: Mensaje 'Centro de Trabajo registrado exitosamente', Accion 'CREADA'.
CALL SP_RegistrarCentroTrabajo('  CT-QA-01  ', '  CENTRO OPERATIVO ALPHA  ', 'CALLE 1 #100', @IdMunA);

-- Guardamos ID para pruebas
SET @IdCT1 = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-QA-01');

-- 1.2. Prueba de Idempotencia (Re-enviar lo mismo)
-- [ESPERADO]: Mensaje '...ya se encuentra registrado', Accion 'REUSADA'.
CALL SP_RegistrarCentroTrabajo('CT-QA-01', 'CENTRO OPERATIVO ALPHA', 'CALLE 1 #100', @IdMunA);

-- 1.3. Prueba de Conflicto de Identidad (Mismo Código, diferente Nombre)
-- [ESPERADO]: 🔴 ERROR: "CONFLICTO DE DATOS: El Código ingresado ya existe..."
CALL SP_RegistrarCentroTrabajo('CT-QA-01', 'CENTRO IMPOSTOR', 'OTRA CALLE', @IdMunA);

-- 1.4. Prueba de Conflicto Físico (Mismo Nombre y Lugar, diferente Código)
-- [ESPERADO]: 🔴 ERROR: "CONFLICTO FÍSICO: Ya existe un Centro de Trabajo con ese NOMBRE..."
CALL SP_RegistrarCentroTrabajo('CT-QA-99', 'CENTRO OPERATIVO ALPHA', 'CALLE 1 #100', @IdMunA);

-- 1.5. Crear un segundo CT (Para pruebas de edición cruzada)
CALL SP_RegistrarCentroTrabajo('CT-QA-02', 'CENTRO OPERATIVO BETA', 'CALLE 2', @IdMunA);
SET @IdCT2 = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-QA-02');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la reconstrucción geográfica (LEFT JOIN) funcione.
   ================================================================================= */

-- 2.1. Consultar Detalle Específico (Para Formulario de Edición)
-- [ESPERADO]: Debe traer Id_Pais, Id_Estado e Id_Municipio correctamente llenos.
CALL SP_ConsultarCentroTrabajoEspecifico(@IdCT1);

-- 2.2. Listado Admin (Vista Plana)
-- [ESPERADO]: Debe mostrar 'PAIS QA A', 'ESTADO QA A', etc.
CALL SP_ListarCTAdmin();

-- 2.3. Listado Activos (Dropdown)
-- [ESPERADO]: Solo código y nombre.
CALL SP_ListarCTActivos();


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD GEOGRÁFICA (PRUEBA DE FUEGO)
   Objetivo: Intentar engañar al sistema con ubicaciones mezcladas.
   ================================================================================= */

-- 3.1. Prueba de "Sin Cambios"
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarCentroTrabajo(@IdCT1, 'CT-QA-01', 'CENTRO OPERATIVO ALPHA', 'CALLE 1 #100', @IdPaisA, @IdEdoA, @IdMunA);

-- 3.2. Prueba de "Mudanza Incoherente" (EL CANDADO ATÓMICO)
-- Intentamos mover el CT diciendo: País A, Estado A... pero MUNICIPIO B (que pertenece al País B).
-- Esto simula un ataque o un bug del frontend.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE INTEGRIDAD: La ubicación seleccionada es inconsistente..."
CALL SP_EditarCentroTrabajo(@IdCT1, 'CT-QA-01', 'CENTRO OPERATIVO ALPHA', 'CALLE 1 #100', @IdPaisA, @IdEdoA, @IdMunB);

-- 3.3. Prueba de Duplicidad Global (Robar código de otro)
-- Intentamos ponerle al CT1 el código del CT2.
-- [ESPERADO]: 🔴 ERROR: "ERROR DE DUPLICIDAD: El Código ingresado ya está en uso..."
CALL SP_EditarCentroTrabajo(@IdCT1, 'CT-QA-02', 'NOMBRE X', 'DIR X', @IdPaisA, @IdEdoA, @IdMunA);

-- 3.4. Edición Correcta (Mudanza Real)
-- Movemos el CT1 de la Ruta A a la Ruta B completamente.
-- [ESPERADO]: Mensaje 'Centro de Trabajo actualizado correctamente', Accion 'ACTUALIZADA'.
CALL SP_EditarCentroTrabajo(@IdCT1, 'CT-QA-01-EDIT', 'CENTRO MUDADO A RUTA B', 'NUEVA CALLE', @IdPaisB, @IdEdoB, @IdMunB);

/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS JERÁRQUICOS
   Objetivo: Verificar que no se pueda activar un CT si su municipio murió.
   ================================================================================= */
/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS JERÁRQUICOS (SECUENCIA CORREGIDA)
   ================================================================================= */

-- 4.1. Primero desactivamos al HIJO (Centro de Trabajo)
-- Esto libera al Municipio para que pueda ser desactivado después.
CALL SP_CambiarEstatusCentroTrabajo(@IdCT1, 0); 
-- [RESULTADO]: Centro de Trabajo Desactivado.

-- 4.2. Ahora sí, desactivamos al PADRE (Municipio B)
-- Como el hijo ya no está activo, el sistema debe permitir apagar el municipio.
CALL SP_CambiarEstatusMunicipio(@IdMunB, 0);
-- [RESULTADO]: Municipio Desactivado. (Activo = 0)

-- 4.3. PRUEBA DE FUEGO: Intentamos REVIVIR al HIJO (CT)
-- Aquí es donde debe saltar el candado, porque su Padre (Municipio B) ahora sí está inactivo.
CALL SP_CambiarEstatusCentroTrabajo(@IdCT1, 1);
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede ACTIVAR... porque su MUNICIPIO está INACTIVO."

-- 4.4. Solución: Reactivar en orden (Arriba hacia Abajo)
CALL SP_CambiarEstatusMunicipio(@IdMunB, 1);    -- Revivimos al Padre
CALL SP_CambiarEstatusCentroTrabajo(@IdCT1, 1); -- Ahora sí deja revivir al Hijo.

/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA
   Objetivo: Limpieza final.
   ================================================================================= */

-- 5.1. Eliminar CT1
CALL SP_EliminarCentroTrabajoFisico(@IdCT1); -- [OK]

-- 5.2. Eliminar CT2
CALL SP_EliminarCentroTrabajoFisico(@IdCT2); -- [OK]

-- 5.3. Limpieza de Ubicaciones de prueba
CALL SP_EliminarMunicipio(@IdMunA);
CALL SP_EliminarEstadoFisico(@IdEdoA);
CALL SP_EliminarPaisFisico(@IdPaisA);

CALL SP_EliminarMunicipio(@IdMunB);
CALL SP_EliminarEstadoFisico(@IdEdoB);
CALL SP_EliminarPaisFisico(@IdPaisB);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO CENTROS DE TRABAJO
   Si viste los errores rojos donde se esperaban, el sistema es seguro.
   ================================================================================= */