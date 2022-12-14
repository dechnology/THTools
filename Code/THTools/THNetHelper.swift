
import UIKit

public class THNetworkHelper<T: Decodable>: NSObject {

    private var hostDomain: String {
        var result = THTools.ToolConstants.netHelperDefaultEndpoint
        if let closure = THTools.ToolConstants.netHelperDomainGetter {
            result = closure()
        }

        return result
    }

    public var showPostBody = false
    public var showResponse = false
    private var strUrl: String = ""
    private var postBody: Any?

    public var modifyRequest: ((URLRequest) -> URLRequest)?
    public var checkResultClosure: ((T?) -> (ok: Bool, err: String))?

    public init(suffix: String = "", body: Any? = nil) {
        super.init()
        self.strUrl = "\(hostDomain)\(suffix)"

        self.postBody = body
        afterInit()
    }

    public init(url: String, body: Any? = nil) {
        super.init()

        self.strUrl = url
        self.postBody = body
        self.afterInit()
    }

    private func afterInit() {
        self.showPostBody = THTools.Logger.nhPostBody
        self.showResponse = THTools.Logger.nhResponse
    }

    private func makeRequest() -> URLRequest? {

        var urlString = strUrl
        if let url = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = url
        }

        guard let url = URL(string: urlString) else {
            return nil
        }
        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        if let post = postBody {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let body = try? JSONSerialization.data(withJSONObject: post, options: .fragmentsAllowed) {
                request.httpBody = body
                if showPostBody {
                    THTools.Logger.netHelper.log("post:\(String.init(data: body, encoding: String.Encoding.utf8) ?? "")")
                }
            }
        }

        if let modifyF = self.modifyRequest {
            request = modifyF(request)
        }

        return request
    }

    public func startRequest(complete: @escaping (THNetworkResponse<T>) -> Void) {

        guard let request = makeRequest() else {
            complete(THNetworkResponse.init(success: false, errMsg: THNetworkError.invalidUrl.rawValue, data: nil, rawData: nil, urlResponse: nil, error: nil))
            return
        }

        THTools.Logger.netHelper.log("start: \(request.url?.absoluteString ?? "unknow")")
        URLSession.shared.dataTask(with: request, completionHandler: { (datSrc, response, error) in
            if let err = error {
                DispatchQueue.main.async {
                    complete(THNetworkResponse.init(success: false, errMsg: err.localizedDescription, data: nil, rawData: datSrc, urlResponse: response, error: error))
                }
                return
            }

            guard let data = datSrc else {
                DispatchQueue.main.async {
                    complete(THNetworkResponse.init(success: false, errMsg: THNetworkError.noData.rawValue, data: nil, rawData: datSrc, urlResponse: response, error: error))
                }
                return
            }
            THTools.Logger.netHelper.log("response of: \(self.strUrl)")
            if self.showResponse {
                THTools.Logger.netHelper.log("\(String.init(data: data, encoding: String.Encoding.utf8) ?? "")")
            } else {
                THTools.Logger.netHelper.log("data.count = \(data.count)")
            }

            let decoder = JSONDecoder()
            let result = try? decoder.decode(T.self, from: data)
            if result == nil {
                THTools.Logger.netHelper.log("unknow data type: \(String.init(data: data, encoding: .utf8) ?? "unknow")")
            }

            if let checker = self.checkResultClosure {
                let rTmp = checker(result)
                if rTmp.ok == false {
                    if result == nil {
                        DispatchQueue.main.async {
                            complete(THNetworkResponse.init(success: false, errMsg: THNetworkError.parseFail.rawValue, data: nil, rawData: data, urlResponse: response, error: error))
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        complete(THNetworkResponse.init(success: false, errMsg: rTmp.err, data: nil, rawData: data, urlResponse: response, error: error))
                    }
                    return
                }
            } else {
                if result == nil {
                    DispatchQueue.main.async {
                        complete(THNetworkResponse.init(success: false, errMsg: THNetworkError.parseFail.rawValue, data: nil, rawData: data, urlResponse: response, error: error))
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                complete(THNetworkResponse.init(success: true, errMsg: "", data: result, rawData: data, urlResponse: response, error: error))
            }
        }).resume()
    }
}

// MARK: - Network Response
public struct THNetworkResponse<T: Decodable> {
    public var success: Bool
    public var errMsg: String
    public var data: T?

    public var rawData: Data?
    public var urlResponse: URLResponse?
    public var error: Error?
}

public enum THNetworkError: String {
    case invalidUrl = "Invalid url"
    case noData = "no data"
    case parseFail = "parse fail"
}
