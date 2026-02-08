/* ======================================================================================================
   ARCHIVO: 17__PROCEDIMIENTOS_PARTICIPANTES_CAPACITACIONES.sql
   ======================================================================================================
   
   SISTEMA: PICADE - Gestión de Capacitaciones
   MÓDULO: Gestión de Participantes (Alumnos e Instructores)
   VERSIÓN: 1.0.0
   
   CONTENIDO:
   ----------
   1. SP_Inscribir_Participante          - Registrar usuario como participante en una capacitación
   2. SP_Dar_Baja_Participante           - Cambiar estatus de participante a BAJA
   3. SP_Actualizar_Resultado_Participante - Actualizar calificación/asistencia de un participante
   4. SP_Obtener_Mis_Cursos              - Historial de capacitaciones del participante (Mi Perfil)
   5. SP_Obtener_Cursos_Impartidos       - Historial de cursos impartidos por instructor
   6. SP_Obtener_Participantes_Capacitacion - Lista de participantes de una capacitación específica
   
   DEPENDENCIAS:
   -------------
   - Vista_Capacitaciones
   - Vista_Gestion_de_Participantes
   - vista_usuarios
   - vista_estatus_participante
   - Cat_Estatus_Participante (IDs hardcoded: 1=INSCRITO, 5=BAJA)
   - Cat_Estatus_Capacitacion (IDs hardcoded para validación de estatus operativos)
   
   ====================================================================================================== */

USE Picade;



/* ======================================================================================================
   FIN DEL ARCHIVO: 17__PROCEDIMIENTOS_PARTICIPANTES_CAPACITACIONES.sql
   ======================================================================================================
   
   RESUMEN DE PROCEDIMIENTOS CREADOS:
   ----------------------------------
   1. SP_Inscribir_Participante          - Registrar usuario como participante (con validación de cupo)
   2. SP_Dar_Baja_Participante           - Cambiar estatus a BAJA (libera cupo)
   3. SP_Actualizar_Resultado_Participante - Actualizar calificación/asistencia
   4. SP_Obtener_Mis_Cursos              - Historial del participante (Latest Snapshot)
   5. SP_Obtener_Cursos_Impartidos       - Historial del instructor (Latest Snapshot)
   6. SP_Obtener_Participantes_Capacitacion - Lista de participantes de un curso
   7. SP_Reinscribir_Participante        - Reactivar participante dado de baja
   
   MAPEO DE ESTATUS DE PARTICIPANTE:
   ---------------------------------
   | ID | Nombre    | Descripción                          |
   |----|-----------|--------------------------------------|
   | 1  | INSCRITO  | Participante registrado en el curso  |
   | 2  | ASISTIÓ   | Participante con asistencia          |
   | 3  | APROBADO  | Calificación >= 70                   |
   | 4  | REPROBADO | Calificación < 70                    |
   | 5  | BAJA      | Dado de baja (libera cupo)           |
   
   ====================================================================================================== */