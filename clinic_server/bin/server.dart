import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// clinic_server — a clinician's own routine, as tools.
///
/// This is the one domain in the series where the line has to be drawn in the
/// code and not only in the prose, so it is drawn twice.
///
/// **This server has no tool that produces a clinical judgement.** No triage,
/// no interpretation, no "likely". What it has is the order of a routine that a
/// clinician wrote down, the readings that instruments already produced, and a
/// record of which steps have been done. Deciding what any of it means is not
/// a tool here, and it is not an omission — it is the design.
///
/// The vocabulary guard below is the second drawing of that line: any string
/// this server would emit is checked against a list of words that would make it
/// sound like a verdict.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Clinic Flow',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  ClinicServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../clinic.mbd');
  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);
  await Completer<void>().future;
}

/// One step of a routine, in the order the clinician put it.
class Step {
  const Step(this.id, this.label, this.needs, this.note);

  final String id;
  final String label;

  /// Readings this step wants in hand before it makes sense to do.
  final List<String> needs;
  final String note;
}

class ClinicServer {
  ClinicServer(this.server);

  final Server server;

  /// The routine. This is the clinician's, the way the plant checklist was the
  /// engineer's — quoted, never paraphrased.
  static const routine = [
    Step('intake', 'Confirm identity and reason for visit', [], ''),
    Step('vitals', 'Record vitals', [], 'device or manual'),
    Step('review', 'Read the last visit note aloud', [], 'catches carried-over items'),
    Step('exam', 'Examination', ['bp', 'hr'], ''),
    Step('plan', 'Agree the plan with the patient', ['bp', 'hr', 'temp'], ''),
    Step('note', 'Write the note before the next patient', [], ''),
  ];

  /// Readings, as the instruments reported them, each with the range the
  /// clinic uses. The range is here so the screen can show a number next to
  /// what it is being compared against — not so the server can call it good.
  final _readings = <String, Map<String, dynamic>>{
    'bp': {'label': 'Blood pressure', 'value': '148/92', 'unit': 'mmHg', 'usual': '<130/80'},
    'hr': {'label': 'Heart rate', 'value': '78', 'unit': 'bpm', 'usual': '60-100'},
    'temp': {'label': 'Temperature', 'value': '36.8', 'unit': 'C', 'usual': '36.1-37.2'},
  };

  final _done = <String>{'intake', 'vitals'};

  /// Words that would turn a report into a verdict. Anything this server is
  /// about to say is checked against them.
  ///
  /// A list of words is a crude guard and it is meant to be. It cannot stop a
  /// determined author, but it does stop the ordinary way this line gets
  /// crossed: someone adds a helpful-sounding summary field months later and
  /// nobody notices that the tool started diagnosing.
  static const forbidden = [
    'diagnos', 'likely', 'suggests', 'consistent with', 'probable',
    'abnormal', 'normal', 'healthy', 'concerning', 'severe', 'mild',
    'recommend', 'should take', 'prescribe',
  ];

  static String _guard(String s) {
    final lower = s.toLowerCase();
    for (final w in forbidden) {
      if (lower.contains(w)) {
        throw StateError('clinic_server tried to emit a judgement word: "$w"');
      }
    }
    return s;
  }

  void register() {
    server.addTool(
      name: 'flow.state',
      description:
          'The routine in order, which steps are done, and the readings each '
          'remaining step wants in hand',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    server.addTool(
      name: 'flow.done',
      description: 'Mark one step of the routine as done',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'step': {'type': 'string'},
        },
        'required': ['step'],
      },
      handler: (args) async {
        final id = args['step'] as String;
        if (!routine.any((s) => s.id == id)) {
          return _state(notice: 'no step called $id');
        }
        _done.add(id);
        return _state(notice: '$id marked done');
      },
    );

    server.addTool(
      name: 'readings.list',
      description:
          'The readings as the instruments reported them, each with the range '
          'the clinic compares against. No interpretation.',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => CallToolResult(content: [
            TextContent(
              text: jsonEncode({
                'readings': _readings.entries
                    .map((e) => {'id': e.key, ...e.value})
                    .toList(),
              }),
            )
          ]),
    );
  }

  CallToolResult _state({String notice = ''}) {
    final steps = routine.map((s) {
      final missing = s.needs.where((n) => !_readings.containsKey(n)).toList();
      return {
        'id': s.id,
        'label': _guard(s.label),
        'done': _done.contains(s.id),
        'needs': s.needs.join(', '),
        'missing': missing.join(', '),
        'note': _guard(s.note),
      };
    }).toList();

    final next = routine.firstWhere((s) => !_done.contains(s.id),
        orElse: () => const Step('', 'Routine complete', [], ''));

    return CallToolResult(content: [
      TextContent(
        text: jsonEncode({
          'steps': steps,
          'stepCount': steps.length,
          // Said on the screen because it is the sample's whole subject: there
          // is no judging tool here, and a word that sounds like a verdict
          // throws before it can be shown.
          'toolRule': 'No tool here judges · readings carry their usual range, '
              'nothing carries a verdict',
          'doneCount': _done.length,
          // "Next" is position in a list the clinician wrote. It is not advice.
          'next': _guard(next.label),
          // What the screen sends back to mark it done: the step's id, never its words.
          'nextId': next.id,
          'nextNeeds': next.needs.join(', '),
          'readings': _readings.entries
              .map((e) => {'id': e.key, ...e.value})
              .toList(),
          'notice': _guard(notice),
        }),
      )
    ]);
  }
}
