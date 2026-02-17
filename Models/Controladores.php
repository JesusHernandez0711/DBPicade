    /**
     * █ MÓDULO: GESTIÓN DOCENTE — MOCK DATA ENGINE (MODO PRUEBA)
     * ──────────────────────────────────────────────────────────────────────
     * @standard Platinum Forensic V.5
     * @status   TESTING MODE (Database Disconnected)
     */
    public function CursosImpartidos()
    {
        //try {
            $idInstructor = Auth::id();
            $hoy = \Carbon\Carbon::now();

            // █ GENERACIÓN DE DATOS SIMULADOS (20 REGISTROS) █
            $dataRaw = [
                // ---------------------------------------------------------
                // GRUPO 1: EN EVALUACIÓN (ID 8) -> DEBE ACTIVAR BOTÓN AMARILLO
                // ---------------------------------------------------------
                (object)[
                    'Id_Detalle_de_Capacitacion' => 801,
                    'Tema_Curso' => 'Seguridad Industrial en Plataformas',
                    'Folio_Curso' => 'CAP-2026-001',
                    'Fecha_Inicio' => $hoy->copy()->subDays(5)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->subDays(1)->format('Y-m-d'), // Terminó ayer
                    'Asistentes_Confirmados' => 18,
                    'Cupo_Programado' => 20,
                    'Id_Estatus_Snapshot' => 8, // <--- CLAVE PARA EVALUAR
                    'Estatus_Snapshot' => 'EN EVALUACIÓN'
                ],
                (object)[
                    'Id_Detalle_de_Capacitacion' => 802,
                    'Tema_Curso' => 'Protocolos de Emergencia V.2',
                    'Folio_Curso' => 'CAP-2026-002',
                    'Fecha_Inicio' => $hoy->copy()->subDays(10)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->subDays(2)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 12,
                    'Cupo_Programado' => 15,
                    'Id_Estatus_Snapshot' => 8, // <--- CLAVE PARA EVALUAR
                    'Estatus_Snapshot' => 'EN EVALUACIÓN'
                ],

                // ---------------------------------------------------------
                // GRUPO 2: EN CURSO (ID 2) -> BADGE AZUL, BOTÓN BLOQUEADO
                // ---------------------------------------------------------
                (object)[
                    'Id_Detalle_de_Capacitacion' => 201,
                    'Tema_Curso' => 'Liderazgo Gerencial PEMEX',
                    'Folio_Curso' => 'CAP-2026-050',
                    'Fecha_Inicio' => $hoy->copy()->subDays(2)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->addDays(2)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 25,
                    'Cupo_Programado' => 25, // Lleno
                    'Id_Estatus_Snapshot' => 2,
                    'Estatus_Snapshot' => 'EN CURSO'
                ],
                (object)[
                    'Id_Detalle_de_Capacitacion' => 202,
                    'Tema_Curso' => 'Excel Avanzado para Ingenieros',
                    'Folio_Curso' => 'CAP-2026-051',
                    'Fecha_Inicio' => $hoy->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->addDays(4)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 8,
                    'Cupo_Programado' => 10,
                    'Id_Estatus_Snapshot' => 2,
                    'Estatus_Snapshot' => 'EN CURSO'
                ],

                // ---------------------------------------------------------
                // GRUPO 3: PROGRAMADOS (ID 1) -> BADGE INFO
                // ---------------------------------------------------------
                (object)[
                    'Id_Detalle_de_Capacitacion' => 101,
                    'Tema_Curso' => 'Introducción a SAP S/4HANA',
                    'Folio_Curso' => 'CAP-2026-100',
                    'Fecha_Inicio' => $hoy->copy()->addMonths(1)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->addMonths(1)->addDays(5)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 5,
                    'Cupo_Programado' => 30,
                    'Id_Estatus_Snapshot' => 1,
                    'Estatus_Snapshot' => 'PROGRAMADO'
                ],
                (object)[
                    'Id_Detalle_de_Capacitacion' => 102,
                    'Tema_Curso' => 'Ética y Valores Corporativos',
                    'Folio_Curso' => 'CAP-2026-101',
                    'Fecha_Inicio' => $hoy->copy()->addWeeks(2)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->addWeeks(2)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 0,
                    'Cupo_Programado' => 50,
                    'Id_Estatus_Snapshot' => 1,
                    'Estatus_Snapshot' => 'PROGRAMADO'
                ],

                // ---------------------------------------------------------
                // GRUPO 4: FINALIZADOS (ID 3) -> BADGE VERDE
                // ---------------------------------------------------------
                (object)[
                    'Id_Detalle_de_Capacitacion' => 301,
                    'Tema_Curso' => 'Inducción 2025',
                    'Folio_Curso' => 'CAP-2025-999',
                    'Fecha_Inicio' => '2025-11-10',
                    'Fecha_Fin'    => '2025-11-12',
                    'Asistentes_Confirmados' => 40,
                    'Cupo_Programado' => 40,
                    'Id_Estatus_Snapshot' => 3,
                    'Estatus_Snapshot' => 'FINALIZADO'
                ],
                (object)[
                    'Id_Detalle_de_Capacitacion' => 302,
                    'Tema_Curso' => 'Mantenimiento de Bombas',
                    'Folio_Curso' => 'CAP-2025-888',
                    'Fecha_Inicio' => '2025-10-01',
                    'Fecha_Fin'    => '2025-10-05',
                    'Asistentes_Confirmados' => 15,
                    'Cupo_Programado' => 15,
                    'Id_Estatus_Snapshot' => 3,
                    'Estatus_Snapshot' => 'FINALIZADO'
                ],

                // ---------------------------------------------------------
                // GRUPO 5: CANCELADOS (ID 4) -> BADGE ROJO
                // ---------------------------------------------------------
                (object)[
                    'Id_Detalle_de_Capacitacion' => 401,
                    'Tema_Curso' => 'Trabajo en Alturas (Suspendido)',
                    'Folio_Curso' => 'CAP-2026-000',
                    'Fecha_Inicio' => $hoy->copy()->subMonths(1)->format('Y-m-d'),
                    'Fecha_Fin'    => $hoy->copy()->subMonths(1)->format('Y-m-d'),
                    'Asistentes_Confirmados' => 0,
                    'Cupo_Programado' => 10,
                    'Id_Estatus_Snapshot' => 4,
                    'Estatus_Snapshot' => 'CANCELADO'
                ],
            ];

            // █ CORRECCIÓN CRÍTICA: HIDRATACIÓN DE COLECCIÓN █
            $cursos = collect($dataRaw);

            // [FASE 3]: DESPACHO DIRECTO
            return view('components.Impartidos', compact('cursos'));

        /*} catch (\Exception $e) {
            $mensajeForense = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('dashboard')->with('danger', 'ERROR MOCK: ' . $mensajeForense);
        }*/
    }

    /*
     * █ MÓDULO: GESTIÓN DOCENTE — MOCK DATA PARTICIPANTES (FULL STRESS TEST)
     * ──────────────────────────────────────────────────────────────────────
     * @standard Platinum Forensic V.5
     * @status   TESTING MODE (Simulación de carga completa: 20-30 pax)
     *
    public function consultarParticipantes(Request $request)
    {
        //try {
            // Validación de seguridad (Simulada)
            $request->validate(['target_hash' => 'required|integer']);
            
            // █ SIMULACIÓN DE NÓMINA (20 PERFILES DISTINTOS) █
            $participantes = [
                // GRUPO 1: INSCRITOS (Estándar)
                (object)['Nombre_Completo' => 'Ing. Roberto Carlos Mendoza', 'Ficha_Usuario' => 'F-58901', 'Nombre_Gerencia' => 'G. de Mantenimiento y Confiabilidad', 'Estatus_Participante' => 'Inscrito'],
                (object)['Nombre_Completo' => 'Lic. Ana Gabriel Solís', 'Ficha_Usuario' => 'F-58902', 'Nombre_Gerencia' => 'G. de Recursos Humanos', 'Estatus_Participante' => 'Inscrito'],
                (object)['Nombre_Completo' => 'Téc. Juan Gabriel López', 'Ficha_Usuario' => 'F-58903', 'Nombre_Gerencia' => 'G. de Operación de Pozos', 'Estatus_Participante' => 'Inscrito'],
                (object)['Nombre_Completo' => 'Ing. Sofia Vergara Cruz', 'Ficha_Usuario' => 'F-58904', 'Nombre_Gerencia' => 'G. de Seguridad Industrial (HSE)', 'Estatus_Participante' => 'Inscrito'],
                (object)['Nombre_Completo' => 'Lic. Luis Miguel Gallego', 'Ficha_Usuario' => 'F-58905', 'Nombre_Gerencia' => 'Subdirección de Finanzas', 'Estatus_Participante' => 'Inscrito'],
                
                // GRUPO 2: ASISTENCIA CONFIRMADA (Para cursos en evaluación)
                (object)['Nombre_Completo' => 'Ing. Guillermo del Toro', 'Ficha_Usuario' => 'F-44201', 'Nombre_Gerencia' => 'G. de Proyectos de Inversión', 'Estatus_Participante' => 'Asistió'],
                (object)['Nombre_Completo' => 'Arq. Frida Kahlo Calderón', 'Ficha_Usuario' => 'F-44202', 'Nombre_Gerencia' => 'G. de Infraestructura', 'Estatus_Participante' => 'Asistió'],
                (object)['Nombre_Completo' => 'Dr. Alfonso Cuarón Orozco', 'Ficha_Usuario' => 'F-44203', 'Nombre_Gerencia' => 'Servicios Médicos', 'Estatus_Participante' => 'Asistió'],
                (object)['Nombre_Completo' => 'Ing. Salma Hayek Jiménez', 'Ficha_Usuario' => 'F-44204', 'Nombre_Gerencia' => 'G. de Perforación', 'Estatus_Participante' => 'Asistió'],
                (object)['Nombre_Completo' => 'Sup. Diego Luna Alexander', 'Ficha_Usuario' => 'F-44205', 'Nombre_Gerencia' => 'G. de Logística y Transporte', 'Estatus_Participante' => 'Asistió'],

                // GRUPO 3: APROBADOS (Éxito Académico)
                (object)['Nombre_Completo' => 'Ing. Mario Molina Pasquel', 'Ficha_Usuario' => 'F-10001', 'Nombre_Gerencia' => 'G. de Protección Ambiental', 'Estatus_Participante' => 'Acreditado'], // ID 3
                (object)['Nombre_Completo' => 'Lic. Sor Juana Inés', 'Ficha_Usuario' => 'F-10002', 'Nombre_Gerencia' => 'G. de Comunicación Social', 'Estatus_Participante' => 'Acreditado'],
                (object)['Nombre_Completo' => 'Ing. Rodolfo Neri Vela', 'Ficha_Usuario' => 'F-10003', 'Nombre_Gerencia' => 'G. de Tecnología de Información', 'Estatus_Participante' => 'Acreditado'],
                (object)['Nombre_Completo' => 'Téc. Cantinflas Moreno', 'Ficha_Usuario' => 'F-10004', 'Nombre_Gerencia' => 'Taller Central de Mantenimiento', 'Estatus_Participante' => 'Acreditado'],
                (object)['Nombre_Completo' => 'Lic. Octavio Paz Lozano', 'Ficha_Usuario' => 'F-10005', 'Nombre_Gerencia' => 'Jurídico Contencioso', 'Estatus_Participante' => 'Acreditado'],

                // GRUPO 4: CASOS NEGATIVOS (Reprobados/Bajas)
                (object)['Nombre_Completo' => 'C. Pedro Infante Cruz', 'Ficha_Usuario' => 'F-99001', 'Nombre_Gerencia' => 'Sindicato Sección 1', 'Estatus_Participante' => 'No Acreditado'], // ID 4
                (object)['Nombre_Completo' => 'C. Jorge Negrete Moreno', 'Ficha_Usuario' => 'F-99002', 'Nombre_Gerencia' => 'Sindicato Sección 1', 'Estatus_Participante' => 'No Acreditado'],
                (object)['Nombre_Completo' => 'Ing. Chespirito Gómez', 'Ficha_Usuario' => 'F-66601', 'Nombre_Gerencia' => 'G. de Auditoría Interna', 'Estatus_Participante' => 'Baja'], // ID 5
                (object)['Nombre_Completo' => 'Lic. Chabelo López', 'Ficha_Usuario' => 'F-66602', 'Nombre_Gerencia' => 'Jubilados y Pensionados', 'Estatus_Participante' => 'Baja'],
                
                // GRUPO 5: EXTERNOS (Sin Ficha Numérica)
                (object)['Nombre_Completo' => 'Consultor Elon Musk', 'Ficha_Usuario' => 'EXT-001', 'Nombre_Gerencia' => 'SpaceX Contractor', 'Estatus_Participante' => 'Inscrito'],
            ];

            // Retorno a la vista parcial
                return view('components.tables.ListaParticipantes', ['alumnos' => $participantes]);
        /*} catch (\Exception $e) {
            // Fail-safe para AJAX
            return response()->json(['error' => 'Error Mock'], 500);
        }
    }*/    