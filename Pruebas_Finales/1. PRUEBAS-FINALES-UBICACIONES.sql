/* =================================================================================
   FASE 1: CREACIÓN Y NORMALIZACIÓN (HAPPY PATH & DATA DIRTY)
   Objetivo: Verificar que se crea la jerarquía y se limpian espacios.
   ================================================================================= */

-- 1.1. Prueba de "Big Bang" (Registrar todo junto)
-- [ESPERADO]: Mensaje 'Registro Exitoso', ids generados y acciones 'CREADA'.
CALL SP_RegistrarUbicaciones('  M_TEST_01  ', '  MUNICIPIO PRUEBA 1  ', 'E_TEST_01', 'ESTADO PRUEBA 1', 'P_TEST_01', 'PAIS PRUEBA 1');

-- Guardamos los IDs generados en variables para usarlos en el resto de pruebas
SET @IdPais1 = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_TEST_01');
SET @IdEdo1  = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_TEST_01');
SET @IdMun1  = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_TEST_01');

-- 1.2. Prueba de Idempotencia (Ejecutar lo mismo otra vez)
-- [ESPERADO]: Mensaje 'Registro Exitoso', pero Acciones deben decir 'REUSADA' (No debe duplicar).
CALL SP_RegistrarUbicaciones('M_TEST_01', 'MUNICIPIO PRUEBA 1', 'E_TEST_01', 'ESTADO PRUEBA 1', 'P_TEST_01', 'PAIS PRUEBA 1');

-- 1.3. Prueba de Inserción Individual (Crear un segundo estado en el mismo país)
-- [ESPERADO]: Accion 'CREADA'
CALL SP_RegistrarEstado('E_TEST_02', 'ESTADO PRUEBA 2', @IdPais1);
SET @IdEdo2 = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_TEST_02');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS (CONSULTAS ESPECÍFICAS Y LISTAS)
   Objetivo: Verificar que la UI reciba los datos correctos y limpios.
   ================================================================================= */

-- 2.1. Consultar la VISTA GLOBAL (Flat View)
-- [ESPERADO]: Debes ver una fila plana con Codigo_Pais, Nombre_Pais, etc.
SELECT * FROM Vista_Direcciones WHERE Id_Municipio = @IdMun1;

-- 2.2. Consultar Detalles Específicos (Para Edición)
-- [ESPERADO]: Datos del municipio + Datos del Estado y País actual.
CALL SP_ConsultarMunicipioEspecifico(@IdMun1);

-- 2.3. Listas para Dropdowns (SOLO ACTIVOS)
-- [ESPERADO]: Debe aparecer 'PAIS PRUEBA 1'.
CALL SP_ListarPaisesActivos();

-- 2.4. Listas Admin (TODOS: Activos e Inactivos)
-- [ESPERADO]: Debe aparecer el país, con Activo=1.
CALL SP_ListarPaisesAdmin();


/* =================================================================================
   FASE 3: INTEGRIDAD Y EDICIÓN (VALIDACIONES DE NEGOCIO)
   Objetivo: Intentar "romper" la lógica con datos inválidos.
   ================================================================================= */

-- 3.1. Intentar registrar un Estado en un País Inexistente
-- [ESPERADO]: 🔴 ERROR: "Id_Pais inválido (dropdown)." o error de FK si falla la validación previa.
CALL SP_RegistrarEstado('ERR', 'ERROR STATE', 99999);

-- 3.2. Intentar Editar Municipio moviéndolo a un Estado que NO pertenece al País seleccionado
-- (Simulamos un ataque o bug del frontend que manda IDs mezclados)
-- [ESPERADO]: 🔴 ERROR: "El Estado destino no pertenece al País seleccionado..."
CALL SP_EditarMunicipio(@IdMun1, 'M_TEST_01', 'MUNICIPIO PRUEBA 1', @IdPais1, 99999); 

-- 3.3. Edición Correcta (Cambio de nombre y código)
-- [ESPERADO]: Mensaje 'Municipio actualizado correctamente'.
CALL SP_EditarMunicipio(@IdMun1, 'M_EDITADO', 'MUNICIPIO RENOMBRADO', @IdPais1, @IdEdo1);

-- 3.4. Verificar "Sin Cambios"
-- [ESPERADO]: Mensaje 'Sin cambios...' y Accion 'SIN_CAMBIOS'.
CALL SP_EditarMunicipio(@IdMun1, 'M_EDITADO', 'MUNICIPIO RENOMBRADO', @IdPais1, @IdEdo1);


/* =================================================================================
   FASE 4: ACTIVAR / DESACTIVAR (BORRADO LÓGICO Y CANDADOS)
   Objetivo: Verificar que no se puedan dejar datos huérfanos activos.
   ================================================================================= */

-- 4.1. Intentar Desactivar PAÍS teniendo hijos activos
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede desactivar el País porque tiene ESTADOS ACTIVOS..."
CALL SP_CambiarEstatusPais(@IdPais1, 0);

-- 4.2. Intentar Desactivar ESTADO teniendo municipios activos
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede desactivar el Estado porque tiene MUNICIPIOS ACTIVOS..."
CALL SP_CambiarEstatusEstado(@IdEdo1, 0);

-- 4.3. Desactivación Correcta (Cascada manual)
-- Paso A: Desactivar Municipio
CALL SP_CambiarEstatusMunicipio(@IdMun1, 0); -- [OK] Mensaje: Desactivado
-- Paso B: Desactivar Estado
CALL SP_CambiarEstatusEstado(@IdEdo1, 0);    -- [OK] Mensaje: Desactivad
-- 1. Desactivar el segundo estado (que se nos había olvidado)
-- [ESPERADO]: Mensaje 'Estado Desactivado'
CALL SP_CambiarEstatusEstado(@IdEdo2, 0);
-- Paso C: Desactivar País (Ahora sí debe dejar)
CALL SP_CambiarEstatusPais(@IdPais1, 0);     -- [OK] Mensaje: Desactivado

-- 4.4. Verificar Listas Activas (Ya no deben aparecer)
-- [ESPERADO]: La lista debe estar VACÍA (o no mostrar P_TEST_01).
CALL SP_ListarPaisesActivos();

-- 4.5. Verificar Listas Admin (Sí deben aparecer como inactivos)
-- [ESPERADO]: P_TEST_01 debe aparecer con Activo = 0.
CALL SP_ListarPaisesAdmin();


/* =================================================================================
   FASE 5: REACTIVACIÓN Y CANDADOS INVERSOS
   Objetivo: Verificar que no se pueda activar un hijo si el padre está muerto.
   ================================================================================= */

-- 5.1. Intentar Activar Municipio (Hijo) cuando Estado y País siguen apagados
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede ACTIVAR el Municipio porque su PAÍS... están INACTIVOS."
CALL SP_CambiarEstatusMunicipio(@IdMun1, 1);

-- 5.2. Intentar Activar Estado (Padre) cuando País sigue apagado
-- [ESPERADO]: 🔴 ERROR: "BLOQUEADO: No se puede ACTIVAR el Estado porque su PAÍS está INACTIVO."
CALL SP_CambiarEstatusEstado(@IdEdo1, 1);

-- 5.3. Reactivación Correcta (Orden ascendente)
CALL SP_CambiarEstatusPais(@IdPais1, 1);     -- Activar Abuelo
CALL SP_CambiarEstatusEstado(@IdEdo1, 1);    -- Activar Padre
CALL SP_CambiarEstatusMunicipio(@IdMun1, 1); -- Activar Hijo (Ahora sí deja)


/* =================================================================================
   FASE 6: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Verificar integridad referencial estricta.
   ================================================================================= */

-- 6.1. Intentar Borrar Físicamente PAÍS con datos
-- [ESPERADO]: 🔴 ERROR CRÍTICO: No se puede eliminar... tiene ESTADOS asociados.
CALL SP_EliminarPaisFisico(@IdPais1);

-- 6.2. Intentar Borrar Físicamente ESTADO con datos
-- [ESPERADO]: 🔴 ERROR CRÍTICO: No se puede eliminar... tiene MUNICIPIOS asociados.
CALL SP_EliminarEstadoFisico(@IdEdo1);

-- 6.3. Borrado Físico Correcto (De abajo hacia arriba)
-- A) Borrar Municipio
CALL SP_EliminarMunicipio(@IdMun1); -- [OK] Eliminado
-- B) Borrar Estado 1
CALL SP_EliminarEstadoFisico(@IdEdo1); -- [OK] Eliminado
-- C) Borrar Estado 2 (el que creamos en paso 1.3)
CALL SP_EliminarEstadoFisico(@IdEdo2); -- [OK] Eliminado
-- D) Borrar País
CALL SP_EliminarPaisFisico(@IdPais1); -- [OK] Eliminado

/* =================================================================================
   FIN DE LAS PRUEBAS
   Si llegaste aquí y viste los mensajes de ERROR ROJO donde se indicaba,
   y los mensajes de ÉXITO donde correspondía, tu sistema está BLINDADO.
   ================================================================================= */