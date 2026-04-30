import XCTest
@testable import SkimLLMCore

final class MarkdownMessageViewTests: XCTestCase {
    func testParsesGitHubStylePipeTable() {
        let markdown = """
        | 方法 | Task Progress（平均 ± 标准误差） |
        |------|-------------------------------|
        | DreamZero（基线） | 38.3% ±7.6% |
        | DreamZero + Human2Robot Transfer（人→机器人迁移，使用约12分钟人类视频数据） | 54.3% ±10.4% |
        | DreamZero + Robot2Robot Transfer（机器人→机器人迁移，使用约20分钟YAM机器人视频数据） | 55.4% ±9.5% |
        """

        let blocks = MarkdownBlockParser.parse(markdown)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(
            blocks,
            [
                .table(
                    headers: ["方法", "Task Progress（平均 ± 标准误差）"],
                    alignments: [.leading, .leading],
                    rows: [
                        ["DreamZero（基线）", "38.3% ±7.6%"],
                        ["DreamZero + Human2Robot Transfer（人→机器人迁移，使用约12分钟人类视频数据）", "54.3% ±10.4%"],
                        ["DreamZero + Robot2Robot Transfer（机器人→机器人迁移，使用约20分钟YAM机器人视频数据）", "55.4% ±9.5%"]
                    ]
                )
            ]
        )
    }

    func testDoesNotTreatIncidentalPipeTextAsTable() {
        let markdown = """
        The notation A | B is used in this paragraph.
        It should stay as normal prose.
        """

        XCTAssertEqual(
            MarkdownBlockParser.parse(markdown),
            [.paragraph("The notation A | B is used in this paragraph.\nIt should stay as normal prose.")]
        )
    }
}
