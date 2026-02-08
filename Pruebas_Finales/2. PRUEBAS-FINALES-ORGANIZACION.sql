/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO ORGANIZACIÓN
   =================================================================================
   OBJETIVO:
   Simular el ciclo de vida completo de los datos (CRUD + Estatus + Eliminación)
   verificando que los candados de seguridad y la integridad referencial funcionen.
   ================================================================================= */

USE Picade;

/* =================================================================================
   FASE 1: CREACIÓN Y NORMALIZACIÓN (HAPPY PATH & DATA DIRTY)
   Objetivo: Verificar que se crea la jerarquía y se limpian espacios.
   ================================================================================= */

-- 1.1. Prueba de "Big Bang" (Registrar todo junto)
-- [ESPERADO]: Mensaje 'Registro Exitoso', ids generados y acciones 'CREADA'.
CALL SP_RegistrarOrganizacion(
    '  G_TEST_01  ', '  GERENCIA PRUEBA 1  ', 
    'S_TEST_01', 'SUBDIRECCION PRUEBA 1', 
    'D_TEST_01', 'DIRECCION PRUEBA 1'
);

-- Guardamos los IDs generados en variables para usarlos en el resto de pruebas
SET @IdDirec1 = (SELECT Id_CatDirecc FROM Cat_Direcciones WHERE Clave = 'D_TEST_01');
SET @IdSubd1  = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'S_TEST_01');
SET @IdGeren1 = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_TEST_01');

-- 1.2. Prueba de Idempotencia (Ejecutar lo mismo otra vez)
-- [ESPERADO]: Mensaje 'Registro Exitoso', pero Acciones deben decir 'REUSADA' (No debe duplicar).
CALL SP_RegistrarOrganizacion(
    'G_TEST_01', 'GERENCIA PRUEBA 1', 
    'S_TEST_01', 'SUBDIRECCION PRUEBA 1', 
    'D_TEST_01', 'DIRECCION PRUEBA 1'
);

-- 1.3. Prueba de Inserción Individual (Crear una segunda Subdirección en la misma Dirección)
-- [ESPERADO]: Accion 'CREADA'
CALL SP_RegistrarSubdireccion('S_TEST_02', 'SUBDIRECCION PRUEBA 2', @IdDirec1);
SET @IdSubd2 = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'S_TEST_02');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS (CONSULTAS ESPECÍFICAS Y LISTAS)
   Objetivo: Verificar que la UI reciba los datos correctos y limpios.
   ================================================================================= */

-- 2.1. Consultar la VISTA GLOBAL (Flat View)
-- [ESPERADO]: Debes ver una fila plana con Clave_Direccion, Nombre_Direccion, etc.
SELECT * FROM Vista_Organizacion WHERE Id_Gerencia = @IdGeren1;

-- 2.2. Consultar Detalles Específicos (Para Edición)
-- [ESPERADO]: Datos de la Gerencia + Datos de Subdirección y Dirección actual.
CALL SP_ConsultarGerenciaEspecifica(@IdGeren1);

-- 2.3. Listas para Dropdowns (SOLO ACTIVOS)
-- [ESPERADO]: Debe aparecer 'DIRECCION PRUEBA 1'.
CALL SP_ListarDireccionesActivas();

-- 2.4. Listas Admin (TODOS: Activos e Inactivos)
-- [ESPERADO]: Debe aparecer la dirección, con Activo=1.
CALL SP_ListarDireccionesAdmin();


/* =================================================================================
   FASE 3: INTEGRIDAD Y EDICIÓN (VALIDACIONES DE NEGOCIO)
   Objetivo: Intentar "romper" la lógica con datos inválidos.
   ================================================================================= */

-- 3.1. Intentar registrar una Subdirección en una Dirección Inexistente
-- [ESPERADO]: 🔴 ERROR: "La Dirección padre no existe."
CALL SP_RegistrarSubdireccion('ERR', 'ERROR SUBDIR', 99999);

-- 3.2. Intentar Editar Gerencia moviéndola a una Subdirección que NO pertenece a la Dirección seleccionada
-- (Simulamos un ataque o bug del frontend que manda IDs mezclados)
-- [ESPERADO]: 🔴 ERROR: "La Subdirección destino no pertenece a la Dirección seleccionada..."
CALL SP_EditarGerencia(@IdGeren1, 'G_TEST_01', 'GERENCIA PRUEBA 1', @IdDirec1, 99999); 

-- 3.3. Edición Correcta (Cambio de nombre y clave)
-- [ESPERADO]: Mensaje 'Gerencia actualizada correctamente'.
CALL SP_EditarGerencia(@IdGeren1, 'G_EDITADO', 'GERENCIA RENOMBRADA', @IdDirec1, @IdSubd1);

-- 3.4. Verificar "Sin Cambios"
-- [ESPERADO]: Mensaje 'Sin cambios...' y Accion 'SIN_CAMBIOS'.
CALL SP_EditarGerencia(@IdGeren1, 'G_EDITADO', 'GERENCIA RENOMBRADA', @IdDirec1, @IdSubd1);


/* =================================================================================
   FASE 4: ACTIVAR / DESACTIVAR (BORRADO LÓGICO Y CANDADOS)
   Objetivo: Verificar que no se puedan dejar datos huérfanos activos.
   ================================================================================= */

-- 4.1. Intentar Desactivar DIRECCIÓN (Abuelo) teniendo hijos activos
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede desactivar la Dirección porque tiene SUBDIRECCIONES ACTIVAS..."
CALL SP_CambiarEstatusDireccion(@IdDirec1, 0);

-- 4.2. Intentar Desactivar SUBDIRECCIÓN (Padre) teniendo gerencias activas
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede desactivar la Subdirección porque tiene GERENCIAS ACTIVAS..."
CALL SP_CambiarEstatusSubdireccion(@IdSubd1, 0);

-- 4.3. Desactivación Correcta (Cascada manual de abajo hacia arriba)
-- Paso A: Desactivar Gerencia
CALL SP_CambiarEstatusGerencia(@IdGeren1, 0);      -- [OK] Mensaje: Desactivada
-- Paso B: Desactivar Subdirección 1
CALL SP_CambiarEstatusSubdireccion(@IdSubd1, 0);   -- [OK] Mensaje: Desactivada
-- 1. Desactivar la segunda Subdirección (la que creamos en paso 1.3)
-- [ESPERADO]: Mensaje 'Subdirección Desactivada'
CALL SP_CambiarEstatusSubdireccion(@IdSubd2, 0);
-- Paso C: Desactivar Dirección (Ahora sí debe dejar porque no tiene hijos activos)
CALL SP_CambiarEstatusDireccion(@IdDirec1, 0);     -- [OK] Mensaje: Desactivada

-- 4.4. Verificar Listas Activas (Ya no deben aparecer)
-- [ESPERADO]: La lista NO debe mostrar D_TEST_01.
CALL SP_ListarDireccionesActivas();

-- 4.5. Verificar Listas Admin (Sí deben aparecer como inactivos)
-- [ESPERADO]: D_TEST_01 debe aparecer con Activo = 0.
CALL SP_ListarDireccionesAdmin();


/* =================================================================================
   FASE 5: REACTIVACIÓN Y CANDADOS INVERSOS
   Objetivo: Verificar que no se pueda activar un hijo si el padre está muerto.
   ================================================================================= */

-- 5.1. Intentar Activar Gerencia (Hijo) cuando Subdirección y Dirección siguen apagados
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede ACTIVAR la Gerencia porque su DIRECCIÓN (Abuelo) está INACTIVA..."
CALL SP_CambiarEstatusGerencia(@IdGeren1, 1);

-- 5.2. Intentar Activar Subdirección (Padre) cuando Dirección sigue apagada
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede ACTIVAR la Subdirección porque su DIRECCIÓN PADRE está INACTIVA..."
CALL SP_CambiarEstatusSubdireccion(@IdSubd1, 1);

-- 5.3. Reactivación Correcta (Orden ascendente)
CALL SP_CambiarEstatusDireccion(@IdDirec1, 1);     -- Activar Abuelo
CALL SP_CambiarEstatusSubdireccion(@IdSubd1, 1);   -- Activar Padre
CALL SP_CambiarEstatusGerencia(@IdGeren1, 1);      -- Activar Hijo (Ahora sí deja)


/* =================================================================================
   FASE 6: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Verificar integridad referencial estricta.
   ================================================================================= */

-- 6.1. Intentar Borrar Físicamente DIRECCIÓN con datos
-- [ESPERADO]: 🔴 ERROR CRÍTICO: No se puede eliminar... tiene SUBDIRECCIONES asociadas.
CALL SP_EliminarDireccionFisica(@IdDirec1);

-- 6.2. Intentar Borrar Físicamente SUBDIRECCIÓN con datos
-- [ESPERADO]: 🔴 ERROR CRÍTICO: No se puede eliminar... tiene GERENCIAS asociadas.
CALL SP_EliminarSubdireccionFisica(@IdSubd1);

-- 6.3. Borrado Físico Correcto (De abajo hacia arriba)
-- A) Borrar Gerencia
CALL SP_EliminarGerenciaFisica(@IdGeren1);      -- [OK] Eliminado
-- B) Borrar Subdirección 1
CALL SP_EliminarSubdireccionFisica(@IdSubd1);   -- [OK] Eliminado
-- C) Borrar Subdirección 2 (paso 1.3)
CALL SP_EliminarSubdireccionFisica(@IdSubd2);   -- [OK] Eliminado
-- D) Borrar Dirección
CALL SP_EliminarDireccionFisica(@IdDirec1);     -- [OK] Eliminado

/* =================================================================================
   FIN DE LAS PRUEBAS
   Si llegaste aquí y viste los mensajes de ERROR ROJO donde se indicaba,
   y los mensajes de ÉXITO donde correspondía, tu sistema de Organización está BLINDADO.
   ================================================================================= */