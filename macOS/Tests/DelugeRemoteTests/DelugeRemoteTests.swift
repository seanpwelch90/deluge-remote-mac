import Foundation
import Testing
@testable import DelugeRemoteCore

@Test func serverURLFromPastedAddress() {
    let server = ServerConfig.make(
        nickname: "NAS",
        host: "https://nas.local:8443/deluge",
        port: 8112,
        path: "",
        useTLS: false,
        allowInvalidCertificate: true
    )
    #expect(server?.hostname == "nas.local")
    #expect(server?.port == 8443)
    #expect(server?.useTLS == true)
    #expect(server?.jsonURL?.absoluteString == "https://nas.local:8443/deluge/json")
}

@Test func defaultJSONEndpoint() throws {
    let server = try #require(ServerConfig.make(
        nickname: "Local",
        host: "127.0.0.1",
        port: 8112,
        path: "",
        useTLS: false,
        allowInvalidCertificate: true
    ))
    #expect(server.jsonURL?.absoluteString == "http://127.0.0.1:8112/json")
}

@Test func hostStatusForBothDelugeGenerations() throws {
    let modern = try JSONDecoder().decode(JSONValue.self, from: Data(#"["abc","Online","2.1.1"]"#.utf8))
    #expect(Host.status(from: modern) == "Online")

    let legacy = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"["abc","127.0.0.1",58846,"Connected","1.3.15"]"#.utf8)
    )
    #expect(Host.status(from: legacy) == "Connected")

    let hosts = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"[["abc","127.0.0.1",58846]]"#.utf8)
    )
    #expect(Host.list(from: hosts).first?.id == "abc")
    #expect(Host.list(from: hosts).first?.port == 58846)
}

@Test func torrentListAndFileProgress() throws {
    let json = try JSONDecoder().decode(JSONValue.self, from: Data(torrentFixture.utf8))
    let torrents = Torrent.list(from: json["result"] ?? .null)
    let torrent = try #require(torrents.first)
    #expect(torrent.name == "Ubuntu")
    #expect(torrent.state == "Downloading")
    #expect(torrent.progress == 50)
    #expect(!torrent.paused)
    #expect(TorrentFilter.downloading.matches(torrent))
    #expect(!TorrentFilter.paused.matches(torrent))

    let detail = try #require(TorrentDetail.parse(hash: torrent.hash, json: json["result"]?["abc"] ?? .null))
    #expect(detail.files.count == 1)
    #expect(abs(detail.files[0].progress - 25) < 0.01)
    #expect(detail.files[0].priority == 1)
    #expect(detail.maxDownloadSpeed == -1)
}

@Test func pausedFilter() throws {
    let pausedJSON = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"{"name":"A","state":"Downloading","paused":true,"label":"tv"}"#.utf8)
    )
    let paused = try #require(Torrent.list(from: .object(["x": pausedJSON])).first)
    #expect(TorrentFilter.paused.matches(paused))
    #expect(!TorrentFilter.downloading.matches(paused))
    #expect(TorrentFilter.label("tv").matches(paused))

    let errorJSON = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"{"name":"A","state":"Error","paused":false}"#.utf8)
    )
    let failed = try #require(Torrent.list(from: .object(["y": errorJSON])).first)
    #expect(TorrentFilter.error.matches(failed))
}

@Test func addOptionsRoundTripKeys() throws {
    let data = try JSONEncoder().encode(AddTorrentOptions.fallback.parameters())
    let object = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(object["add_paused"]?.bool == false)
    #expect(object["max_download_speed"]?.int == -1)
}

@Test func serverDirectoryRoundTrip() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var store = ClientDirectory(directory: directory, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
    let server = try #require(ServerConfig.make(
        nickname: "Office",
        host: "10.0.0.8",
        port: 8112,
        path: "deluge",
        useTLS: false,
        allowInvalidCertificate: false
    ))
    store.saveServers([server])
    #expect(store.loadServers() == [server])
    store.selectedServerID = server.id
    #expect(store.selectedServerID == server.id)
    store.setPassword("secret", for: server.id)
    #expect(store.password(for: server.id) == "secret")
    let serversFile = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(!serversFile.contains("secret"))
    store.deletePassword(for: server.id)
    #expect(store.password(for: server.id).isEmpty)
}

@Test func magnetAndTorrentFileImports() {
    let magnet = URL(string: "magnet:?xt=urn:btih:abc&dn=Example")!
    #expect(TorrentImport.parse(url: magnet) == .magnet(magnet.absoluteString))
    #expect(TorrentImport.parse(text: "  magnet:?xt=urn:btih:abc") == .magnet("magnet:?xt=urn:btih:abc"))

    let file = URL(fileURLWithPath: "/tmp/example.torrent")
    #expect(TorrentImport.parse(url: file) == .torrentFile(file))
    #expect(TorrentImport.parse(url: URL(fileURLWithPath: "/tmp/notes.txt")) == nil)
    #expect(TorrentImport.parse(text: "https://example.com/file.torrent") == nil)
}

private let torrentFixture = """
{
  "result": {
    "abc": {
      "name": "Ubuntu",
      "hash": "abc",
      "paused": false,
      "progress": 50,
      "state": "Downloading",
      "ratio": 0.5,
      "download_payload_rate": 1000,
      "upload_payload_rate": 10,
      "total_wanted": 200,
      "total_size": 200,
      "eta": 30,
      "tracker_host": "tracker.example",
      "label": "linux",
      "time_added": 1700000000,
      "all_time_download": 100,
      "total_uploaded": 5,
      "save_path": "/downloads",
      "max_download_speed": -1.0,
      "max_upload_speed": -1,
      "max_connections": -1,
      "num_seeds": 3,
      "num_peers": 8,
      "files": [{ "index": 0, "path": "ubuntu.iso", "size": 200 }],
      "file_progress": [0.25],
      "file_priorities": [1]
    }
  }
}
"""
