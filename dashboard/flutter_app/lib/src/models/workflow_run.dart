class WorkflowRun {
  final int id;
  final String name;
  final String displayTitle;
  final String status;
  final String? conclusion;
  final String branch;
  final String sha;
  final String event;
  final String createdAt;
  final String url;
  final int runNumber;
  final String actor;
  final String duration;

  WorkflowRun({
    required this.id,
    required this.name,
    required this.displayTitle,
    required this.status,
    this.conclusion,
    required this.branch,
    required this.sha,
    required this.event,
    required this.createdAt,
    required this.url,
    required this.runNumber,
    required this.actor,
    required this.duration,
  });

  factory WorkflowRun.fromJson(Map<String, dynamic> json) => WorkflowRun(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        displayTitle: json['display_title'] ?? json['name'] ?? '',
        status: json['status'] ?? '',
        conclusion: json['conclusion'],
        branch: json['branch'] ?? '',
        sha: json['sha'] ?? '',
        event: json['event'] ?? '',
        createdAt: json['created_at'] ?? '',
        url: json['url'] ?? '',
        runNumber: json['run_number'] ?? 0,
        actor: json['actor'] ?? '',
        duration: json['duration'] ?? '',
      );

  bool get isSuccess => conclusion == 'success';
  bool get isFailure => conclusion == 'failure';
  bool get isRunning => status == 'in_progress' || status == 'queued';
}

class Workflow {
  final int id;
  final String name;
  final String state;
  final String path;
  final String url;

  Workflow({
    required this.id,
    required this.name,
    required this.state,
    required this.path,
    required this.url,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) => Workflow(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        state: json['state'] ?? '',
        path: json['path'] ?? '',
        url: json['url'] ?? '',
      );
}
