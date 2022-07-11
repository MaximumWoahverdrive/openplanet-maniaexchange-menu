class MapTab : Tab
{
    Net::HttpRequest@ m_MXrequest;
    Net::HttpRequest@ m_MXAuthorsRequest;
    Net::HttpRequest@ m_TMIOrequest;
    Net::HttpRequest@ m_MXEmbedObjRequest;
    MX::MapInfo@ m_map;
    array<MX::MapAuthorInfo@> m_authors;
    array<TMIO::Leaderboard@> m_leaderboard;
    int m_mapId;
    bool m_isLoading = false;
    bool m_mapDownloaded = false;
    bool m_isMapOnPlayLater = false;
    bool m_error = false;
    bool m_authorsError = false;
    bool m_TMIOrequestStart = false;
    bool m_TMIOrequestStarted = false;
    bool m_TMIOstopleaderboard = false;
    bool m_TMIOerror = false;
    string m_TMIOerrorMsg = "";
    bool m_TMIONoRes = false;
    array<MX::MapEmbeddedObject@> m_mapEmbeddedObjects;
    bool m_mapEmbeddedObjectsError = false;

    UI::Font@ g_fontHeader;

    MapTab(int trackId) {
        @g_fontHeader = UI::LoadFont("DroidSans-Bold.ttf", 24);
        m_mapId = trackId;
        StartMXRequest();
        StartMXAuthorsRequest();
    }

    bool CanClose() override { return !m_isLoading; }

    string GetLabel() override {
        if (m_error) {
            m_isLoading = false;
            return "\\$f00"+Icons::Times+" \\$zError";
        }
        if (m_map is null) {
            m_isLoading = true;
            return Icons::Map+" Loading...";
        } else {
            m_isLoading = false;
            string res = Icons::Map+" ";
            if (Setting_ColoredMapName) res += ColoredString(m_map.GbxMapName);
            else res += m_map.Name;
            return res;
        }
    }

    void StartMXRequest()
    {
        string url = "https://"+MXURL+"/api/maps/get_map_info/multi/"+m_mapId;
        if (IsDevMode()) print("MapTab::StartRequest (MX): "+url);
        @m_MXrequest = API::Get(url);
    }

    void CheckMXRequest()
    {
        // If there's a request, check if it has finished
        if (m_MXrequest !is null && m_MXrequest.Finished()) {
            // Parse the response
            string res = m_MXrequest.String();
            if (IsDevMode()) print("MapTab::CheckRequest (MX): " + res);
            @m_MXrequest = null;
            auto json = Json::Parse(res);

            if (json.get_Length() == 0) {
                print("MapTab::CheckRequest (MX): Error parsing response");
                HandleMXResponseError();
                return;
            }
            // Handle the response
            HandleMXResponse(json[0]);
        }
    }

    void HandleMXResponse(const Json::Value &in json)
    {
        @m_map = MX::MapInfo(json);
    }

    void HandleMXResponseError()
    {
        m_error = true;
    }

    void StartMXAuthorsRequest()
    {
        string url = "https://"+MXURL+"/api/maps/get_authors/"+m_mapId;
        if (IsDevMode()) trace("MapTab::StartRequest (Authors): "+url);
        @m_MXAuthorsRequest = API::Get(url);
    }

    void CheckMXAuthorsRequest()
    {
        // If there's a request, check if it has finished
        if (m_MXAuthorsRequest !is null && m_MXAuthorsRequest.Finished()) {
            // Parse the response
            string res = m_MXAuthorsRequest.String();
            if (IsDevMode()) trace("MapTab::CheckRequest (Authors): " + res);
            @m_MXAuthorsRequest = null;
            auto json = Json::Parse(res);

            if (json.get_Length() == 0) {
                print("MapTab::CheckRequest (Authors): Error parsing response");
                HandleMXAuthorsResponseError();
                return;
            }
            // Handle the response
            HandleMXAuthorResponse(json);
        }
    }

    void HandleMXAuthorResponse(const Json::Value &in json)
    {
        for (uint i = 0; i < json.get_Length(); i++) {
            MX::MapAuthorInfo@ author = MX::MapAuthorInfo(json[i]);
            m_authors.InsertLast(author);
        }
    }

    void HandleMXAuthorsResponseError()
    {
        m_authorsError = true;
    }

    void StartTMIORequest(int offset = 0)
    {
        if (m_map is null) return;
        string url = "https://trackmania.io/api/leaderboard/map/"+m_map.TrackUID;
        if (offset != -1) url += "?length=100&offset=" + offset;
        if (IsDevMode()) trace("MapTab::StartRequest (TM.IO): "+url);
        m_TMIOrequestStarted = true;
        @m_TMIOrequest = API::Get(url);
    }

    void CheckTMIORequest()
    {
        // If there's a request, check if it has finished
        if (m_TMIOrequest !is null && m_TMIOrequest.Finished()) {
            // Parse the response
            string res = m_TMIOrequest.String();
            if (IsDevMode()) trace("MapTab::CheckRequest (TM.IO): " + res);
            @m_TMIOrequest = null;
            auto json = Json::Parse(res);

            // if error, handle it (particular case for "not found on API")
            if (json.HasKey("error")){
                HandleTMIOResponseError(json["error"]);
            } else {
                // if tops is null return no results, else handle the response
                if (json["tops"].GetType() == Json::Type::Null) {
                    if (IsDevMode()) print("MapTab::CheckRequest (TM.IO): No results");
                    m_TMIONoRes = true;
                }
                else HandleTMIOResponse(json["tops"]);
            }
            m_TMIOrequestStarted = false;
        }
    }

    void HandleTMIOResponse(const Json::Value &in json)
    {
        if (json.get_Length() < 100) m_TMIOstopleaderboard = true;

        for (uint i = 0; i < json.get_Length(); i++) {
            auto leaderboard = TMIO::Leaderboard(json[i]);
            m_leaderboard.InsertLast(leaderboard);
        }
    }

    void HandleTMIOResponseError(string error)
    {
        m_TMIOerror = true;
        if (error.Contains("does not exist")) {
            m_TMIOerrorMsg = "This map is not available on Nadeo Services";
        } else {
            m_TMIOerrorMsg = error;
        }
    }

    void StartMXEmbeddedRequest()
    {
        string url = "https://"+MXURL+"/api/maps/embeddedobjects/"+m_mapId;
        if (IsDevMode()) trace("MapTab::StartRequest (Embedded): "+url);
        @m_MXEmbedObjRequest = API::Get(url);
    }

    void CheckMXEmbeddedRequest()
    {
        if (!MX::APIDown && m_mapEmbeddedObjects.Length != m_map.EmbeddedObjectsCount && m_MXEmbedObjRequest is null && UI::IsWindowAppearing()) {
            StartMXEmbeddedRequest();
        }
        // If there's a request, check if it has finished
        if (m_MXEmbedObjRequest !is null && m_MXEmbedObjRequest.Finished()) {
            // Parse the response
            string res = m_MXEmbedObjRequest.String();
            if (IsDevMode()) trace("MapTab::CheckRequest (Embedded): " + res);
            @m_MXEmbedObjRequest = null;
            auto json = Json::Parse(res);

            if (json.Length == 0) {
                print("MapTab::CheckRequest (Embedded): Error parsing response");
                m_mapEmbeddedObjectsError = true;
                return;
            }
            // Handle the response
            for (uint i = 0; i < json.Length; i++) {
                MX::MapEmbeddedObject@ object = MX::MapEmbeddedObject(json[i], int(i) < Setting_EmbeddedObjectsLimit);
                m_mapEmbeddedObjects.InsertLast(object);
            }
        }
    }

    string FormatTime(int time) {
        int hundreths = time % 1000;
        time /= 1000;
        int hours = time / 3600;
        int minutes = (time / 60) % 60;
        int seconds = time % 60;

        return (hours != 0 ? Text::Format("%02d", hours) + ":" : "" ) + (minutes != 0 ? Text::Format("%02d", minutes) + ":" : "") + Text::Format("%02d", seconds) + "." + Text::Format("%03d", hundreths);
    }

    void Render() override
    {
        CheckMXRequest();
        CheckMXAuthorsRequest();

        if (m_error) {
            UI::Text("\\$f00" + Icons::Times + " \\$zMap not found");
            return;
        }

        if (m_map is null) {
            int HourGlassValue = Time::Stamp % 3;
            string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
            UI::Text(Hourglass + " Loading...");
            return;
        }

        // Check if the map is already on the play later list
        for (uint i = 0; i < g_PlayLaterMaps.get_Length(); i++) {
            MX::MapInfo@ playLaterMap = g_PlayLaterMaps[i];
            if (playLaterMap.TrackID != m_map.TrackID) {
                m_isMapOnPlayLater = false;
            } else {
                m_isMapOnPlayLater = true;
                break;
            }
        }

        float width = UI::GetWindowSize().x*0.35;
        vec2 posTop = UI::GetCursorPos();

        UI::BeginChild("Summary", vec2(width,0));

        UI::BeginTabBar("MapImages");

        if (m_map.ImageCount != 0) {
            for (uint i = 1; i < m_map.ImageCount+1; i++) {
                if(UI::BeginTabItem(tostring(i))){
                    auto img = Images::CachedFromURL("https://"+MXURL+"/maps/"+m_map.TrackID+"/image/"+i);

                    if (img.m_texture !is null){
                        vec2 thumbSize = img.m_texture.GetSize();
                        UI::Image(img.m_texture, vec2(
                            width,
                            thumbSize.y / (thumbSize.x / width)
                        ));
                        if (UI::IsItemHovered()) {
                            UI::BeginTooltip();
                            UI::Image(img.m_texture, vec2(
                                Draw::GetWidth() * 0.6,
                                thumbSize.y / (thumbSize.x / (Draw::GetWidth() * 0.6))
                            ));
                            UI::EndTooltip();
                        }
                    } else {
                        int HourGlassValue = Time::Stamp % 3;
                        string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
                        UI::Text(Hourglass + " Loading");
                    }
                    UI::EndTabItem();
                }
            }
        }

        if(UI::BeginTabItem("Thumbnail")){
            auto thumb = Images::CachedFromURL("https://"+MXURL+"/maps/thumbnail/"+m_map.TrackID);
            if (thumb.m_texture !is null){
                vec2 thumbSize = thumb.m_texture.GetSize();
                UI::Image(thumb.m_texture, vec2(
                    width,
                    thumbSize.y / (thumbSize.x / width)
                ));
                if (UI::IsItemHovered()) {
                    UI::BeginTooltip();
                    UI::Image(thumb.m_texture, vec2(
                        Draw::GetWidth() * 0.4,
                        thumbSize.y / (thumbSize.x / (Draw::GetWidth() * 0.4))
                    ));
                    UI::EndTooltip();
                }
            } else {
                int HourGlassValue = Time::Stamp % 3;
                string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
                UI::Text(Hourglass + " Loading");
            }
            UI::EndTabItem();
        }

        UI::EndTabBar();
        UI::Separator();

        for (uint i = 0; i < m_map.Tags.Length; i++) {
            IfaceRender::MapTag(m_map.Tags[i]);
            UI::SameLine();
        }
        UI::NewLine();

        UI::Text(Icons::Trophy + " \\$f77" + m_map.AwardCount);
        UI::SetPreviousTooltip("Awards");
#if MP4
        if (repo == MP4mxRepos::Shootmania) {
            UI::Text(Icons::FileCodeO + " \\$f77" + m_map.MapType);
            UI::SetPreviousTooltip("Map Type");
        } else {
#endif
        UI::Text(Icons::Hourglass + " \\$f77" + m_map.LengthName);
        UI::SetPreviousTooltip("Length");
#if MP4
        }
#endif
        if (m_map.Laps >= 1) {
            UI::Text(Icons::Refresh+ " \\$f77" + m_map.Laps);
            UI::SetPreviousTooltip("Laps");
        }
        UI::Text(Icons::LevelUp+ " \\$f77" + m_map.DifficultyName);
        UI::SetPreviousTooltip("Difficulty");

        UI::Text(Icons::Hashtag+ " \\$f77" + m_map.TrackID);
        UI::SetPreviousTooltip("Track ID");
        UI::SameLine();
        UI::TextDisabled(Icons::Clipboard);
        UI::SetPreviousTooltip("Click to copy to clipboard");
        if (UI::IsItemClicked()) {
            IO::SetClipboard(tostring(m_map.TrackID));
            UI::ShowNotification(Icons::Clipboard + " Track ID copied to clipboard");
        }

        UI::Text(Icons::Calendar + " \\$f77" + m_map.UploadedAt);
        UI::SetPreviousTooltip("Uploaded date");
        if (m_map.UploadedAt != m_map.UpdatedAt) {
            UI::Text(Icons::Refresh + " \\$f77" + m_map.UpdatedAt);
            UI::SetPreviousTooltip("Updated date");
        }
#if MP4
        UI::Text(Icons::Inbox + " \\$f77" + m_map.TitlePack);
        UI::SetPreviousTooltip("Title Pack");
#endif
        UI::Text(Icons::Sun + " \\$f77" + m_map.Mood);
        UI::SetPreviousTooltip("Mood");
        UI::Text(Icons::Money + " \\$f77" + m_map.DisplayCost);
        UI::SetPreviousTooltip("Coppers cost");
        if (UI::CyanButton(Icons::ExternalLink + " View on "+pluginName)) OpenBrowserURL("https://"+MXURL+"/maps/"+m_map.TrackID);
#if TMNEXT
        if (UI::Button(Icons::ExternalLink + " View on Trackmania.io")) OpenBrowserURL("https://trackmania.io/#/leaderboard/"+m_map.TrackUID);
#endif

#if TMNEXT
        if (Permissions::PlayLocalMap()) {
#endif

            Json::Value SupportedModes = MX::ModesFromMapType();
            if (!SupportedModes.HasKey(m_map.MapType)) {
                UI::Text("\\$f70" + Icons::ExclamationTriangle + " \\$zThe map type is not supported for direct play\nit can crash your game or returns you to the menu");
                if (!Setting_ShowPlayOnAllMaps) {
                    UI::SetPreviousTooltip("If you still want to play this map, check the box \"Show Play Button on all map types\" in the plugin settings");
                }
                if (Setting_ShowPlayOnAllMaps && UI::OrangeButton(Icons::Play + " Play Map Anyway")) {
                    if (UI::IsOverlayShown() && Setting_CloseOverlayOnLoad) UI::HideOverlay();
                    UI::ShowNotification("Loading map...", ColoredString(m_map.GbxMapName) + "\\$z\\$s by " + m_map.Username);
                    UI::ShowNotification(Icons::ExclamationTriangle + " Warning", "The map type is not supported for direct play, it can crash your game or returns you to the menu", UI::HSV(0.11, 1.0, 1.0), 15000);
                    MX::mapToLoad = m_map.TrackID;
                }
            } else {
                if (UI::GreenButton(Icons::Play + " Play Map")) {
                    if (UI::IsOverlayShown() && Setting_CloseOverlayOnLoad) UI::HideOverlay();
                    UI::ShowNotification("Loading map...", ColoredString(m_map.GbxMapName) + "\\$z\\$s by " + m_map.Username);
                    MX::mapToLoad = m_map.TrackID;
                }
            }
#if TMNEXT
        } else {
            UI::Text("\\$f00"+Icons::Times + " \\$zYou do not have permissions to play");
            UI::Text("Consider buying at least standard access of the game.");
        }
#endif

        if (MX::mapDownloadInProgress){
            UI::Text("\\$f70" + Icons::Download + " \\$zDownloading map...");
            m_isLoading = true;
        } else {
            m_isLoading = false;
            if (!m_mapDownloaded) {
                if (UI::PurpleButton(Icons::Download + " Download Map")) {
                    UI::ShowNotification("Downloading map...", ColoredString(m_map.GbxMapName) + "\\$z\\$s by " + m_map.Username);
                    MX::mapToDL = m_map.TrackID;
                    m_mapDownloaded = true;
                }
            } else {
                UI::Text("\\$0f0" + Icons::Download + " \\$zMap downloaded");
                UI::TextDisabled("to " + "Maps\\Downloaded\\"+pluginName+"\\" + m_map.TrackID + " - " + m_map.Name + ".Map.Gbx");
                if (UI::RoseButton(Icons::FolderOpen + " Open Containing Folder")) OpenExplorerPath(IO::FromUserGameFolder("Maps/Downloaded/"+pluginName));
            }
        }

        if (!m_isMapOnPlayLater){
#if TMNEXT
            if (Permissions::PlayLocalMap() && UI::GreenButton(Icons::Check + " Add to Play later")) {
#else
            if (UI::GreenButton(Icons::Check + " Add to Play later")) {
#endif
                g_PlayLaterMaps.InsertAt(0, m_map);
                m_isMapOnPlayLater = true;
                SavePlayLater(g_PlayLaterMaps);
            }
        } else {
#if TMNEXT
            if (Permissions::PlayLocalMap() && UI::RedButton(Icons::Check + " Remove from Play later")) {
#else
            if (UI::RedButton(Icons::Times + " Remove from Play later")) {
#endif
                for (uint i = 0; i < g_PlayLaterMaps.get_Length(); i++) {
                    MX::MapInfo@ playLaterMap = g_PlayLaterMaps[i];
                    if (playLaterMap.TrackID == m_map.TrackID) {
                        g_PlayLaterMaps.RemoveAt(i);
                        m_isMapOnPlayLater = false;
                        SavePlayLater(g_PlayLaterMaps);
                    }
                }
            }
        }

        UI::EndChild();

        UI::SetCursorPos(posTop + vec2(width + 8, 0));
        UI::BeginChild("Description");

        UI::PushFont(g_fontHeader);
        UI::Text(ColoredString(m_map.GbxMapName));
        UI::PopFont();

        if (m_authorsError) {
            UI::TextDisabled("By " + m_map.Username);
        } else {
            // check if array is empty
            if (m_authors.get_Length() > 0) {
                UI::TextDisabled("By: ");
                UI::SameLine();
                for (uint i = 0; i < m_authors.get_Length(); i++) {
                    MX::MapAuthorInfo@ author = m_authors[i];
                    UI::TextDisabled(author.Username + (i == m_authors.get_Length() - 1 ? "" : ", "));
                    if (UI::IsItemHovered()) {
                        UI::BeginTooltip();
                        if (author.Uploader) {
                            UI::Text(Icons::CloudUpload + " Uploader");
                            UI::Separator();
                        }
                        if (author.Role != "") {
                            UI::Text(author.Role);
                            UI::Separator();
                        }
                        UI::TextDisabled("Click to see "+author.Username+"'s profile");
                        UI::EndTooltip();
                    }
                    if (UI::IsItemClicked()) mxMenu.AddTab(UserTab(author.UserID), true);
                    if (i < m_authors.get_Length() - 1) UI::SameLine();
                }
            } else {
                int HourGlassValue = Time::Stamp % 3;
                string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
                UI::TextDisabled(Hourglass + " By " + m_map.Username);
            }
        }

        if (m_map.SizeWarning)
            UI::Text("\\$f70" + Icons::ExclamationTriangle + " \\$zThis map is larger than 6MB and therefore can not be played on servers.");

        UI::Separator();

        UI::BeginTabBar("MapTabs");

        if(UI::BeginTabItem("Description")){
            UI::BeginChild("MapDescriptionChild");
            IfaceRender::MXComment(m_map.Comments);
            UI::EndChild();
            UI::EndTabItem();
        }
#if TMNEXT
        if(UI::BeginTabItem("Online Leaderboard")){
            UI::BeginChild("MapLeaderboardChild");

            CheckTMIORequest();
            if (m_TMIOrequestStart) {
                m_TMIOrequestStart = false;
                if (!m_TMIONoRes && m_leaderboard.get_Length() == 0) StartTMIORequest();
                else {
                    if (!m_TMIONoRes) {
                        StartTMIORequest(m_leaderboard.get_Length());
                    }
                }
            }

            if (m_TMIOerror){
                UI::Text("\\$f00" + Icons::Times + "\\$z "+ m_TMIOerrorMsg);
            } else {
                UI::Text(Icons::Heartbeat + " The leaderboard is fetched directly from Trackmania.io (Nadeo Services)");
                UI::SameLine();
                if (UI::OrangeButton(Icons::Refresh)){
                    m_leaderboard.RemoveRange(0, m_leaderboard.get_Length());
                    if (!m_TMIOrequestStarted) m_TMIOrequestStart = true;
                    m_TMIOstopleaderboard = false;
                }

                if (!m_TMIOstopleaderboard && m_leaderboard.get_Length() == 0) {
                    if (m_TMIONoRes) {
                        UI::Text("No records found for this map. Be the first!");
                    } else {
                        if (!m_TMIOrequestStarted) m_TMIOrequestStart = true;
                        int HourGlassValue = Time::Stamp % 3;
                        string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
                        UI::Text(Hourglass + " Loading...");
                    }
                } else {
                    if (UI::BeginTable("LeaderboardList", 3)) {
                        UI::TableSetupScrollFreeze(0, 1);
                        PushTabStyle();
                        UI::TableSetupColumn("Position", UI::TableColumnFlags::WidthFixed, 40);
                        UI::TableSetupColumn("Player", UI::TableColumnFlags::WidthStretch);
                        UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthStretch);
                        UI::TableHeadersRow();
                        PopTabStyle();
                        UI::ListClipper clipper(m_leaderboard.Length);
                        while(clipper.Step()) {
                            for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
                                UI::TableNextRow();
                                TMIO::Leaderboard@ entry = m_leaderboard[i];

                                UI::TableSetColumnIndex(0);
                                UI::Text(tostring(entry.position));

                                UI::TableSetColumnIndex(1);
                                UI::Text(entry.playerName);

                                UI::TableSetColumnIndex(2);
                                UI::Text(FormatTime(entry.time));
                                if (i != 0){
                                    UI::SameLine();
                                    UI::Text("\\$f00(+ " + FormatTime(entry.time - m_leaderboard[0].time) + ")");
                                }
                            }
                        }
                        UI::EndTable();
                        if (!m_TMIOrequestStarted && !m_TMIOstopleaderboard && UI::GreenButton("Load more")){
                            m_TMIOrequestStart = true;
                        }
                        if (m_TMIOrequestStarted && !m_TMIOstopleaderboard){
                            UI::Text(Icons::HourglassEnd + " Loading...");
                        }
                    }
                }
            }
            UI::EndChild();
            UI::EndTabItem();
        }
#endif

        if(m_map.EmbeddedObjectsCount > 0 && UI::BeginTabItem("Embedded objects (" + m_map.EmbeddedObjectsCount + ")")){
            UI::BeginChild("MapEmbeddedObjectsChild");

            CheckMXEmbeddedRequest();
            if (m_mapEmbeddedObjects.Length != m_map.EmbeddedObjectsCount) {
                int HourGlassValue = Time::Stamp % 3;
                string Hourglass = (HourGlassValue == 0 ? Icons::HourglassStart : (HourGlassValue == 1 ? Icons::HourglassHalf : Icons::HourglassEnd));
                UI::Text(Hourglass + " Loading...");
            } else {
                UI::Text(m_mapEmbeddedObjects.Length + " objects found, with a total size of " + (m_map.EmbeddedItemsSize / 1024) + " KB");
                if (UI::BeginTable("EmbeddedObjectsList", 3)) {
                    UI::TableSetupScrollFreeze(0, 1);
                    PushTabStyle();
                    UI::TableSetupColumn("Name", UI::TableColumnFlags::WidthStretch);
                    UI::TableSetupColumn("Author", UI::TableColumnFlags::WidthStretch);
                    UI::TableSetupColumn("Action", UI::TableColumnFlags::WidthFixed, 40);
                    UI::TableHeadersRow();
                    PopTabStyle();
                    UI::ListClipper clipper(m_mapEmbeddedObjects.Length);
                    while(clipper.Step()) {
                        for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++) {
                            UI::TableNextRow();
                            MX::MapEmbeddedObject@ object = m_mapEmbeddedObjects[i];
                            UI::PushID("EmbeddedObject" + i);

                            UI::TableSetColumnIndex(0);
                            UI::Text(object.Name);

                            UI::TableSetColumnIndex(1);
                            if (object.Username.Length == 0) UI::TextDisabled(object.ObjectAuthor);
                            else UI::Text(object.Username);
                            if (object.UserID > 0) {
                                UI::SetPreviousTooltip("Click to see "+(object.Username.Length > 0 ? (object.Username+"'s") : "user")+" profile");
                                if (UI::IsItemClicked()) mxMenu.AddTab(UserTab(object.UserID), true);
                            }

                            UI::TableSetColumnIndex(2);
                            if (object.ID != 0){
                                if (object.ID == -1) {
                                    UI::Text("\\$f00" + Icons::Times);
                                    UI::SetPreviousTooltip("Error while fetching this object on item.exchange");
                                } else if (object.ID == -2) {
                                    UI::TextDisabled(Icons::ExclamationTriangle);
                                    UI::SetPreviousTooltip("The list of embedded objects is too long for this map.");
                                } else {
                                    if (UI::YellowButton(Icons::ExternalLink)){
                                        OpenBrowserURL("https://item.exchange/item/view/"+object.ID);
                                    }
                                }
                            } else {
                                UI::TextDisabled(Icons::Times);
                                UI::SetPreviousTooltip("This object is not published on item.exchange");
                            }
                            UI::PopID();
                        }
                    }
                    UI::EndTable();
                }
            }
            UI::EndChild();
            UI::EndTabItem();
        }

        UI::EndTabBar();

        UI::EndChild();
    }
}