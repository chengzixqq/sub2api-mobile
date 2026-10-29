import Foundation
import Sub2Core

/// The filter sheet's shares under `-ui-testing` (40 §1.2): the range's actual cost by group and by requested model. Group ids are
/// DemoData's account groups, the App's only group fixture (X05); 0 is usage without a group, 测试组 (6, inactive) has none.
extension AnalyticsFixtures {
    static func groupShares() throws -> [AnalyticsBreakdown] {
        try filterRows("""
        [{"group_id":1,"group_name":"高级组","requests":1820,"total_tokens":48200000,"actual_cost":"182.40","account_cost":"96.10"},
         {"group_id":2,"group_name":"标准组","requests":960,"total_tokens":21400000,"actual_cost":"96.10","account_cost":"51.20"},
         {"group_id":3,"group_name":"默认组","requests":410,"total_tokens":9800000,"actual_cost":"40.00","account_cost":"22.30"},
         {"group_id":5,"group_name":"Claude Code 组","requests":230,"total_tokens":6100000,"actual_cost":"21.50","account_cost":"12.40"},
         {"group_id":0,"group_name":"","requests":95,"total_tokens":1900000,"actual_cost":"10.00","account_cost":"6.00"}]
        """)
    }
    static func filterModels() throws -> [AnalyticsBreakdown] {
        try filterRows("""
        [{"model":"gpt-5","requests":1100,"total_tokens":30100000,"actual_cost":"92.40","account_cost":"50.10"},
         {"model":"claude-opus-4","requests":1210,"total_tokens":35800000,"actual_cost":"180.20","account_cost":"94.00"},
         {"model":"deepseek-v3","requests":620,"total_tokens":11200000,"actual_cost":"41.30","account_cost":"22.80"},
         {"model":"gemini-2.5-pro","requests":380,"total_tokens":7300000,"actual_cost":"26.10","account_cost":"14.90"},
         {"model":"glm-4.6","requests":195,"total_tokens":3000000,"actual_cost":"10.00","account_cost":"6.20"}]
        """)
    }

    private static func filterRows(_ json: String) throws -> [AnalyticsBreakdown] {
        try JSONDecoder().decode([AnalyticsBreakdown].self, from: Data(json.utf8))
    }
}
