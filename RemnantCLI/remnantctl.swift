import Foundation

@main
enum RemnantCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "mcp", arguments.dropFirst().first == "serve" {
            AgentMCPServer.run()
            return
        }

        let result = AgentCommandService.run(arguments: arguments)
        if !result.stdout.isEmpty {
            fputs(result.stdout, stdout)
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr, stderr)
        }
        exit(result.exitCode)
    }
}
